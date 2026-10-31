import 'dart:async';
import 'dart:typed_data';

import 'package:marieum_app/core/audio/recording_engine.dart';
import 'package:marieum_app/core/audio/voice_audio_session.dart';
import 'package:marieum_app/core/error/failure.dart';

/// An open microphone delivering PCM16 16 kHz mono chunks until stopped.
/// Nothing is kept; listeners decide what to send.
class MicStream {
  MicStream({
    required this._engine,
    required this._permission,
    required this._audioSession,
    this.echoCancel = false,
  });

  /// iOS voice processing weakens and reshapes speech enough to hurt
  /// recognition, so only Android turns echo cancellation on.
  final bool echoCancel;

  final RecordingEngine _engine;
  final MicrophonePermission _permission;
  final VoiceAudioSession _audioSession;
  bool _open = false;

  Future<Stream<Uint8List>> start() async {
    final access = await _permission.request();
    if (access != MicrophoneAccess.granted) {
      throw PermissionFailure(permanent: access == MicrophoneAccess.permanent);
    }
    await _audioSession.configure();
    final stream = await _engine.startStream(echoCancel: echoCancel);
    _open = true;
    return stream.map(Uint8List.fromList);
  }

  Future<void> stop() async {
    if (!_open) return;
    _open = false;
    await _engine.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _engine.dispose();
  }
}
