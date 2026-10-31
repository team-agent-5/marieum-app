import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:marieum_app/core/audio/recorded_audio.dart';
import 'package:marieum_app/core/audio/recording_engine.dart';
import 'package:marieum_app/core/audio/voice_audio_session.dart';
import 'package:marieum_app/core/error/failure.dart';

class Recorder {
  Recorder({
    required this._engine,
    required this._permission,
    required this._audioSession,
    Timer Function(Duration, void Function())? createTimer,
  }) : _createTimer = createTimer ?? Timer.new;

  static const maxDuration = Duration(seconds: 10);
  static const maxPcmBytes = 320000;
  final RecordingEngine _engine;
  final MicrophonePermission _permission;
  final VoiceAudioSession _audioSession;
  final Timer Function(Duration, void Function()) _createTimer;
  Future<void>? _starting;
  _Recording? _current;
  bool _disposed = false;
  final _levels = StreamController<double>.broadcast();
  final _chunks = StreamController<Uint8List>.broadcast(sync: true);

  /// Input loudness of each captured chunk, 0 (silence) to 1 (loud).
  Stream<double> get levels => _levels.stream;

  /// Captured PCM16 chunks as they arrive, capped like the recording itself.
  Stream<Uint8List> get chunks => _chunks.stream;

  Future<RecordedAudio> get completed {
    final current = _current;
    if (current == null) throw StateError('No recording has started.');
    return current.result.future;
  }

  Future<void> start() {
    if (_disposed ||
        _starting != null ||
        (_current != null && !_current!.result.isCompleted)) {
      throw StateError('Recorder is unavailable or already recording.');
    }
    return _starting = _start();
  }

  Future<void> _start() async {
    try {
      final access = await _permission.request();
      if (access != MicrophoneAccess.granted) {
        throw PermissionFailure(
          permanent: access == MicrophoneAccess.permanent,
        );
      }
      if (_disposed) throw StateError('Recorder is disposed.');
      await _audioSession.configure();
      if (_disposed) throw StateError('Recorder is disposed.');
      final stream = await _engine.startStream();
      final current = _Recording();
      _current = current;
      current
        ..result.future.ignore()
        ..subscription = stream.listen(
          (chunk) {
            final room = maxPcmBytes - current.length;
            final count = chunk.length < room ? chunk.length : room;
            if (count > 0) {
              final bytes = Uint8List.fromList(chunk.sublist(0, count));
              current
                ..pcm.add(bytes)
                ..length += count;
              if (!_levels.isClosed) _levels.add(pcmLevel(chunk));
              if (!_chunks.isClosed) _chunks.add(bytes);
            }
            if (current.length == maxPcmBytes) unawaited(_finish(current));
          },
          onError: (Object error, StackTrace stack) {
            current
              ..error = error
              ..stack = stack;
            unawaited(_finish(current));
          },
          onDone: () {
            if (!current.ended.isCompleted) current.ended.complete();
            unawaited(_finish(current));
          },
        )
        ..timer = _createTimer(
          maxDuration,
          () => unawaited(_finish(current)),
        );
    } finally {
      _starting = null;
    }
  }

  Future<RecordedAudio> stop() async {
    await _starting;
    final current = _current;
    if (current == null) throw StateError('No recording has started.');
    unawaited(_finish(current));
    return current.result.future;
  }

  Future<void> _finish(_Recording current) async {
    if (current.finishing) return;
    current.finishing = true;
    current.timer?.cancel();
    try {
      await _engine.stop();
      // Some platforms omit onDone after stop; retain the captured PCM.
      await current.ended.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
      if (current.error != null) {
        Error.throwWithStackTrace(current.error!, current.stack!);
      }
      final result = encodePcmWav(current.pcm.takeBytes());
      await current.subscription?.cancel();
      current.result.complete(result);
    } on Object catch (error, stack) {
      current.pcm.clear();
      await current.subscription?.cancel();
      current.result.completeError(error, stack);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      try {
        await _starting;
      } on Object {
        /* A failed start still needs disposal. */
      }
      final current = _current;
      if (current != null) {
        unawaited(_finish(current));
        try {
          await current.result.future;
        } on Object {
          /* Discard capture errors on disposal. */
        }
      }
    } finally {
      await _levels.close();
      await _chunks.close();
      await _engine.dispose();
    }
  }
}

/// Maps PCM16 little-endian RMS onto a 0..1 scale spanning -50 dBFS to 0.
double pcmLevel(List<int> chunk) {
  final samples = chunk.length ~/ 2;
  if (samples == 0) return 0;
  final data = ByteData.sublistView(Uint8List.fromList(chunk));
  var sum = 0.0;
  for (var i = 0; i < samples; i++) {
    final sample = data.getInt16(i * 2, Endian.little) / 32768;
    sum += sample * sample;
  }
  final rms = math.sqrt(sum / samples);
  if (rms <= 0) return 0;
  final db = 20 * math.log(rms) / math.ln10;
  return ((db + 50) / 50).clamp(0, 1).toDouble();
}

class _Recording {
  final pcm = BytesBuilder();
  int length = 0;
  final result = Completer<RecordedAudio>();
  final ended = Completer<void>();
  // Recorder._finish cancels this on success, failure and disposal.
  // ignore: cancel_subscriptions
  StreamSubscription<List<int>>? subscription;
  Timer? timer;
  Object? error;
  StackTrace? stack;
  bool finishing = false;
}
