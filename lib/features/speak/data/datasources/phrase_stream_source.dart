import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/log/app_log.dart';
import 'package:marieum_app/core/network/session_expiry_signal.dart';
import 'package:marieum_app/core/storage/secure_token_store.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:marieum_app/features/speak/domain/repositories/live_stream.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Live mode transcription over `/ws/phrase/stream`: one WebSocket for the
/// whole session, binary PCM frames up, JSON transcripts down. The server's
/// recognizer (conversation mode) decides where sentences end.
class PhraseStreamSource implements LiveStream {
  PhraseStreamSource({
    required this.endpoint,
    required this._tokens,
    required this._expiry,
    WebSocketChannel Function(Uri)? connect,
    this.retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ],
  }) : _connect = connect ?? WebSocketChannel.connect;

  /// Derives `wss://host/ws/phrase/stream` from the API address.
  static Uri endpointFor(String baseUrl) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      scheme: base.scheme == 'http' || base.scheme == 'ws' ? 'ws' : 'wss',
      path: '/ws/phrase/stream',
    );
  }

  final Uri endpoint;
  final SecureTokenStore _tokens;
  final SessionExpirySignal _expiry;
  final WebSocketChannel Function(Uri) _connect;

  /// Waits between attempts while the server cannot be reached; the last
  /// one repeats.
  final List<Duration> retryDelays;

  @override
  LiveConversation connect() {
    final conversation = _Conversation(this);
    unawaited(conversation.run());
    return conversation;
  }
}

class _Conversation implements LiveConversation {
  _Conversation(this._source);

  /// 100 ms of PCM16 16 kHz mono.
  static const frameBytes = 3200;

  /// Audio kept while reconnecting so a sentence in progress survives.
  static const backlogFrames = 30;

  /// Gap between kept frames when sending them after reconnecting.
  static const catchUpGap = Duration(milliseconds: 50);
  static const _unauthorized = 4001;

  final PhraseStreamSource _source;
  final _events = StreamController<LiveEvent>();
  final _pending = BytesBuilder(copy: false);
  final _backlog = <Uint8List>[];
  WebSocketChannel? _channel;
  bool _open = false;
  bool _closed = false;

  @override
  Stream<LiveEvent> get events => _events.stream;

  @override
  void add(Uint8List audio) {
    if (_closed) return;
    _pending.add(audio);
    while (_pending.length >= frameBytes) {
      final bytes = _pending.takeBytes();
      _frame(Uint8List.sublistView(bytes, 0, frameBytes));
      if (bytes.length > frameBytes) {
        _pending.add(Uint8List.sublistView(bytes, frameBytes));
      }
    }
  }

  void _frame(Uint8List frame) {
    if (_open && _backlog.isEmpty) {
      _channel?.sink.add(frame);
      return;
    }
    _backlog.add(frame);
    if (!_open && _backlog.length > backlogFrames) _backlog.removeAt(0);
  }

  /// Sends audio kept while reconnecting at twice its real pace, new audio
  /// queued behind it, so the recognizer does not get seconds at once.
  Future<void> _catchUp(WebSocketChannel channel) async {
    while (_open && _channel == channel && _backlog.isNotEmpty) {
      channel.sink.add(_backlog.removeAt(0));
      await Future<void>.delayed(catchUpGap);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_open) _channel?.sink.add(jsonEncode({'type': 'cancel'}));
    AppLog.ws('-> cancel, closing');
    _open = false;
    await _channel?.sink.close();
    await _events.close();
  }

  void _emit(LiveEvent event) {
    if (!_closed) _events.add(event);
  }

  Future<void> run() async {
    var failures = 0;
    while (!_closed) {
      final outcome = await _attempt();
      if (_closed || outcome == _Outcome.stop) return;
      if (outcome == _Outcome.reconnect) {
        failures = 0;
        continue;
      }
      failures++;
      if (failures == _source.retryDelays.length) {
        _emit(const LiveFailed(NetworkFailure()));
      }
      final delays = _source.retryDelays;
      await Future<void>.delayed(
        delays[failures <= delays.length ? failures - 1 : delays.length - 1],
      );
    }
  }

  Future<_Outcome> _attempt() async {
    String? token;
    try {
      token = await _source._tokens.read();
    } on Object {
      // Treated as signed out below.
    }
    if (_closed) return _Outcome.stop;
    if (token == null || token.isEmpty) {
      _emit(const LiveFailed(UnauthorizedFailure(), recovering: false));
      return _Outcome.stop;
    }
    final endpoint = _source.endpoint;
    final channel = _channel = _source._connect(
      endpoint.replace(queryParameters: {'token': token}),
    );
    final started = DateTime.now();
    try {
      await channel.ready;
    } on Object catch (error) {
      AppLog.ws('connect ${endpoint.path} failed (${error.runtimeType})');
      return _Outcome.failed;
    }
    if (_closed) {
      unawaited(channel.sink.close());
      return _Outcome.stop;
    }
    AppLog.ws(
      'open ${endpoint.path} '
      '${DateTime.now().difference(started).inMilliseconds}ms, '
      'backlog ${_backlog.length} frames',
    );
    _open = true;
    unawaited(_catchUp(channel));
    try {
      await for (final message in channel.stream) {
        if (message is String) _receive(message);
        if (_closed) break;
      }
    } on Object catch (error) {
      AppLog.ws('stream error (${error.runtimeType})');
    }
    _open = false;
    final code = channel.closeCode;
    AppLog.ws('closed $code');
    if (_closed) return _Outcome.stop;
    if (code == _unauthorized) {
      _source._expiry.emit();
      _emit(const LiveFailed(UnauthorizedFailure(), recovering: false));
      return _Outcome.stop;
    }
    // The server may close after each sentence or at its length limit; the
    // conversation simply carries on over a new connection.
    return _Outcome.reconnect;
  }

  void _receive(String message) {
    final Object? json;
    try {
      json = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (json is! Map<String, Object?>) return;
    final traceId = json['trace_id'] as String? ?? '';
    switch (json['type']) {
      case 'transcript':
        final text = _clean(json['text'] as String? ?? '');
        if (json['final'] != true) {
          AppLog.ws('<- interim "$text"');
          if (text.isNotEmpty) _emit(LiveInterim(text));
          return;
        }
        final confidence = (json['confidence'] as num?)?.toDouble() ?? 0;
        AppLog.ws(
          '<- final "$text" $confidence is_last=${json['is_last']} '
          'trace $traceId',
        );
        _emit(
          text.isEmpty
              ? const LiveUnclear()
              : LiveFinal(
                  Transcription(
                    traceId: traceId,
                    finalTranscript: text,
                    asrConfidence: confidence,
                  ),
                ),
        );
      case 'error':
        final code = json['error_code'] as String?;
        AppLog.ws('<- error $code trace $traceId');
        switch (code) {
          case 'ASR_LOW_CONFIDENCE':
            _emit(const LiveUnclear());
          case 'UNAUTHORIZED':
            _source._expiry.emit();
            _emit(const LiveFailed(UnauthorizedFailure(), recovering: false));
          default:
            // The connection closes after this and is reopened.
            break;
        }
      case 'end_notice':
        AppLog.ws('<- end_notice ${json['reason']}');
    }
  }

  /// The recognizer sometimes splits a Hangul syllable and sends the broken
  /// half as U+FFFD; it is dropped and the rest of the sentence kept.
  static String _clean(String text) =>
      text.replaceAll('\uFFFD', '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
}

enum _Outcome { reconnect, failed, stop }
