import 'dart:async';
import 'dart:convert';

import 'package:marieum_app/core/log/app_log.dart';
import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';
import 'package:marieum_app/features/listen/domain/repositories/listener_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The other phone's `/ws/listen`: authenticated by the subprotocols
/// `marieum.listen.v1` and the listener token, `say` and `session_end` down,
/// `played` up.
class ListenerSocket implements ListenerChannel {
  ListenerSocket({
    required this.endpoint,
    WebSocketChannel Function(Uri, Iterable<String>)? connect,
    this.retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ],
    this.offlineLimit = const Duration(seconds: 35),
    this.silenceLimit = const Duration(seconds: 40),
    DateTime Function()? now,
  }) : _connect =
           connect ??
           ((uri, protocols) =>
               WebSocketChannel.connect(uri, protocols: protocols)),
       _now = now ?? DateTime.now;

  static const protocol = 'marieum.listen.v1';

  /// Derives `wss://host/ws/listen` from the API address.
  static Uri endpointFor(String baseUrl) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      scheme: base.scheme == 'http' || base.scheme == 'ws' ? 'ws' : 'wss',
      path: '/ws/listen',
    );
  }

  final Uri endpoint;
  final WebSocketChannel Function(Uri, Iterable<String>) _connect;
  final DateTime Function() _now;

  /// Waits between attempts while the server cannot be reached; the last
  /// one repeats.
  final List<Duration> retryDelays;

  /// How long without a connection before giving up. The server holds the
  /// listener's place for 30 seconds after a drop.
  final Duration offlineLimit;

  /// How long an open connection may go without a frame; the server pings
  /// every 25 seconds.
  final Duration silenceLimit;

  @override
  ListenerConnection connect(ListenerPass pass) {
    final connection = _Connection(this, pass);
    unawaited(connection.run());
    return connection;
  }
}

enum _Outcome { ended, dropped, failed }

class _Connection implements ListenerConnection {
  _Connection(this._socket, this._pass);

  static const _tokenInvalid = 4001;
  static const _sessionOver = 4004;
  static const _otherDevice = 4009;

  final ListenerSocket _socket;
  final ListenerPass _pass;
  final _events = StreamController<ListenerEvent>();
  WebSocketChannel? _channel;
  bool _closed = false;

  @override
  Stream<ListenerEvent> get events => _events.stream;

  @override
  void played(String utteranceId) {
    final channel = _channel;
    if (_closed || channel == null) return;
    channel.sink.add(
      jsonEncode({'type': 'played', 'utterance_id': utteranceId}),
    );
    AppLog.ws('-> played $utteranceId');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _channel?.sink.close();
    await _events.close();
  }

  Future<void> run() async {
    var failures = 0;
    var offlineSince = _socket._now();
    while (!_closed) {
      var heard = false;
      var outcome = await _attempt(onHeard: () => heard = true);
      if (_closed || outcome == _Outcome.ended) return;
      if (outcome == _Outcome.dropped) {
        // Only a connection the server spoke on was working; one that closed
        // or stayed silent is no better than none, so it waits like one
        // rather than reconnecting in a tight loop.
        if (heard) {
          failures = 0;
          offlineSince = _socket._now();
        } else {
          outcome = _Outcome.failed;
        }
      }
      if (_socket._now().difference(offlineSince) >= _socket.offlineLimit ||
          _socket._now().isAfter(_pass.expiresAt)) {
        _end(ListenEndReason.connectionLost);
        return;
      }
      _emit(const ListenerReconnecting());
      final delays = _socket.retryDelays;
      final wait = delays[failures.clamp(0, delays.length - 1)];
      // A drop is tried again at once; an attempt that never opened waits.
      if (outcome == _Outcome.failed) {
        failures++;
        await Future<void>.delayed(wait);
      }
    }
  }

  Future<_Outcome> _attempt({required void Function() onHeard}) async {
    final endpoint = _socket.endpoint;
    final channel = _channel = _socket._connect(endpoint, [
      ListenerSocket.protocol,
      _pass.token,
    ]);
    try {
      await channel.ready;
    } on Object catch (error) {
      AppLog.ws('connect ${endpoint.path} failed (${error.runtimeType})');
      return _closed ? _Outcome.ended : _Outcome.failed;
    }
    if (_closed) {
      unawaited(channel.sink.close());
      return _Outcome.ended;
    }
    AppLog.ws('open ${endpoint.path}');
    _emit(const ListenerConnected());
    final done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    var ended = false;
    var silent = false;
    var heard = false;
    Timer? silence;
    // The server pings every 25 seconds; a connection that says nothing for
    // longer is dead even if it was never closed.
    void watch() {
      silence?.cancel();
      silence = Timer(_socket.silenceLimit, () {
        silent = true;
        finish();
      });
    }

    watch();
    final subscription = channel.stream.listen(
      (message) {
        watch();
        if (!heard) {
          heard = true;
          onHeard();
        }
        if (message is String && _receive(message)) {
          ended = true;
          finish();
        }
        if (_closed) finish();
      },
      onError: (Object error) =>
          AppLog.ws('stream error (${error.runtimeType})'),
      onDone: finish,
    );
    await done.future;
    silence?.cancel();
    if (ended || _closed || silent) {
      unawaited(subscription.cancel());
      unawaited(channel.sink.close());
      if (silent && !_closed && !ended) {
        AppLog.ws(
          'silent for ${_socket.silenceLimit.inSeconds}s, reconnecting',
        );
        return _Outcome.dropped;
      }
      return _Outcome.ended;
    }
    final code = channel.closeCode;
    AppLog.ws('closed $code');
    final reason = switch (code) {
      _tokenInvalid => ListenEndReason.tokenInvalid,
      _sessionOver => ListenEndReason.expired,
      _otherDevice => ListenEndReason.otherDevice,
      _ => null,
    };
    if (reason != null) {
      _end(reason);
      return _Outcome.ended;
    }
    return _Outcome.dropped;
  }

  /// Handles one message; true once the session is over.
  bool _receive(String message) {
    final Object? json;
    try {
      json = jsonDecode(message);
    } on FormatException {
      return false;
    }
    if (json is! Map<String, Object?>) return false;
    switch (json['type']) {
      case 'say':
        final id = json['utterance_id'];
        final text = json['text'];
        if (id is! String || text is! String || text.trim().isEmpty) {
          return false;
        }
        AppLog.ws('<- say $id server_ts ${json['server_ts']}');
        _emit(ListenerSay(utteranceId: id, text: text.trim()));
      case 'session_end':
        AppLog.ws('<- session_end ${json['reason']}');
        _end(switch (json['reason']) {
          'patient_left' => ListenEndReason.patientLeft,
          'revoked' => ListenEndReason.revoked,
          _ => ListenEndReason.expired,
        });
        return true;
      // `ping` keeps the connection open and needs no answer.
    }
    return false;
  }

  void _end(ListenEndReason reason) {
    _emit(ListenerEnded(reason));
    _closed = true;
    unawaited(_channel?.sink.close());
    unawaited(_events.close());
  }

  void _emit(ListenerEvent event) {
    if (!_closed && !_events.isClosed) _events.add(event);
  }
}
