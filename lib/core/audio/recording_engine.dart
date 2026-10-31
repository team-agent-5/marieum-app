import 'package:duplex_audio/duplex_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

enum MicrophoneAccess { granted, denied, permanent }

// A named adapter boundary supports dependency injection and mocktail.
// ignore: one_member_abstracts
abstract interface class MicrophonePermission {
  Future<MicrophoneAccess> request();
}

class PlatformMicrophonePermission implements MicrophonePermission {
  @override
  Future<MicrophoneAccess> request() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) return MicrophoneAccess.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return MicrophoneAccess.permanent;
    }
    return MicrophoneAccess.denied;
  }
}

abstract interface class RecordingEngine {
  /// [echoCancel] removes the app's own playback from the input, for
  /// listening while speaking.
  Future<Stream<List<int>>> startStream({bool echoCancel = false});
  Future<void> stop();
  Future<void> dispose();
}

class PlatformRecordingEngine implements RecordingEngine {
  PlatformRecordingEngine({AudioRecorder? plugin})
    : _plugin = plugin ?? AudioRecorder();
  final AudioRecorder _plugin;

  @override
  Future<Stream<List<int>>> startStream({bool echoCancel = false}) =>
      _plugin.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: echoCancel,
          androidConfig: AndroidRecordConfig(
            // Android applies echo cancellation reliably only to the
            // communication source; otherwise the recognition source avoids
            // gain and noise shaping that blur weak consonants.
            audioSource: echoCancel
                ? AndroidAudioSource.voiceCommunication
                : AndroidAudioSource.voiceRecognition,
          ),
        ),
      );
  @override
  Future<void> stop() async {
    await _plugin.stop();
  }

  @override
  Future<void> dispose() => _plugin.dispose();
}

/// iOS live mode: the microphone of the engine that also plays the app's
/// voice, so echo cancellation can remove that voice. Apple's gain control
/// and a little make-up gain keep speech strong after processing.
class DuplexRecordingEngine implements RecordingEngine {
  DuplexRecordingEngine({DuplexAudio? audio})
    : _audio = audio ?? DuplexAudio.instance;

  static const gainDb = 6.0;

  final DuplexAudio _audio;

  @override
  Future<Stream<List<int>>> startStream({bool echoCancel = false}) =>
      _audio.start(gainDb: gainDb);

  @override
  Future<void> stop() => _audio.stop();

  @override
  Future<void> dispose() => _audio.stop();
}
