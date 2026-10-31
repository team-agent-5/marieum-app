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

/// Live mode transcription over `/ws/phrase/stream`: one WebSocket per
/// utterance, binary PCM frames up, JSON transcripts down.
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
    this.finalTimeout = const Duration(seconds: 8),
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

  /// Waits between reconnects when the connection or the server's speech
  /// recognizer is unavailable.
  final List<Duration> retryDelays;

  /// How long the final transcript may take after the patient pauses.
  final Duration finalTimeout;

  @override
  LiveUtterance open() {
    final session = _Session(this);
    unawaited(session.run());
    return session;
  }
}

class _Session implements LiveUtterance {
  _Session(this._source);

  /// 100 ms of PCM16 16 kHz mono.
  static const frameBytes = 3200;
  static const _upstreamDown = 4503;
  static const _unauthorized = 4001;

  final PhraseStreamSource _source;
  final _events = StreamController<LiveEvent>();
  final _frames = <Uint8List>[];
  final _pending = BytesBuilder(copy: false);
  WebSocketChannel? _channel;
  bool _open = false;
  bool _ended = false;
  bool _done = false;
  Timer? _finalTimer;

  @override
  Stream<LiveEvent> get events => _events.stream;

  @override
  bool get isClosed => _done;

  @override
  void add(Uint8List audio) {
    if (_done || _ended) return;
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
    _frames.add(frame);
    if (_open) _channel?.sink.add(frame);
  }

  @override
  void end() {
    if (_done || _ended) return;
    if (_pending.isNotEmpty) _frame(_pending.takeBytes());
    _ended = true;
    if (_open) _sendEnd();
    _finalTimer = Timer(_source.finalTimeout, () {
      AppLog.ws('no final in ${_source.finalTimeout.inSeconds}s');
      _finish(const LiveFailed(TimeoutFailure()));
    });
  }

  void _sendEnd() {
    _channel?.sink.add(jsonEncode({'type': 'end'}));
    AppLog.ws('-> ${_frames.length} frames, end');
  }

  @override
  void cancel() {
    if (_done) return;
    if (_open) _channel?.sink.add(jsonEncode({'type': 'cancel'}));
    AppLog.ws('-> cancel');
    _finish(null);
  }

  void _finish(LiveEvent? event) {
    if (_done) return;
    _done = true;
    _finalTimer?.cancel();
    if (event != null) _events.add(event);
    unawaited(_events.close());
    unawaited(_channel?.sink.close());
  }

  Future<void> run() async {
    for (var attempt = 0; ; attempt++) {
      final retry = await _attempt(attempt);
      if (_done) return;
      if (!retry || attempt >= _source.retryDelays.length) {
        _finish(const LiveFailed(NetworkFailure()));
        return;
      }
      await Future<void>.delayed(_source.retryDelays[attempt]);
      if (_done) return;
    }
  }

  /// Returns whether a reconnect may help.
  Future<bool> _attempt(int attempt) async {
    final String? token;
    try {
      token = await _source._tokens.read();
    } on Object {
      _finish(const LiveFailed(UnauthorizedFailure()));
      return false;
    }
    if (_done) return false;
    if (token == null || token.isEmpty) {
      _finish(const LiveFailed(UnauthorizedFailure()));
      return false;
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
      return true;
    }
    if (_done) {
      unawaited(channel.sink.close());
      return false;
    }
    AppLog.ws(
      'open ${endpoint.path} attempt ${attempt + 1} '
      '${DateTime.now().difference(started).inMilliseconds}ms',
    );
    _open = true;
    _frames.forEach(channel.sink.add);
    if (_ended) _sendEnd();
    var retry = false;
    try {
      await for (final message in channel.stream) {
        if (message is! String) continue;
        retry = _receive(message);
        if (_done) break;
      }
    } on Object catch (error) {
      AppLog.ws('stream error (${error.runtimeType})');
    }
    _open = false;
    final code = channel.closeCode;
    AppLog.ws('closed $code');
    if (_done) return false;
    if (code == _unauthorized) {
      _source._expiry.emit();
      _finish(const LiveFailed(UnauthorizedFailure()));
      return false;
    }
    return retry || code == _upstreamDown || code == null;
  }

  /// Handles one server message; returns whether it asks for a reconnect.
  bool _receive(String message) {
    final Object? json;
    try {
      json = jsonDecode(message);
    } on FormatException {
      return false;
    }
    if (json is! Map<String, Object?>) return false;
    final traceId = json['trace_id'] as String? ?? '';
    switch (json['type']) {
      case 'transcript':
        final text = (json['text'] as String? ?? '').trim();
        if (json['final'] != true) {
          AppLog.ws('<- interim "$text"');
          if (text.isNotEmpty) _events.add(LiveInterim(text));
          return false;
        }
        final confidence = (json['confidence'] as num?)?.toDouble() ?? 0;
        AppLog.ws('<- final "$text" $confidence trace $traceId');
        _finish(
          LiveFinal(
            Transcription(
              traceId: traceId,
              finalTranscript: text,
              asrConfidence: confidence,
            ),
          ),
        );
      case 'error':
        final code = json['error_code'] as String?;
        final text = json['message'] as String?;
        AppLog.ws('<- error $code trace $traceId');
        switch (code) {
          case 'ASR_LOW_CONFIDENCE':
            _finish(const LiveUnclear());
          case 'ML_UPSTREAM_UNAVAILABLE':
            return true;
          case 'UNAUTHORIZED':
            _source._expiry.emit();
            _finish(const LiveFailed(UnauthorizedFailure()));
          default:
            _finish(
              LiveFailed(
                ServerFailure(
                  statusCode: null,
                  message: text ?? '일시적인 문제가 생겼어요.',
                  errorCode: code,
                  traceId: traceId,
                ),
              ),
            );
        }
      case 'end_notice':
        AppLog.ws('<- end_notice ${json['reason']}');
    }
    return false;
  }
}
