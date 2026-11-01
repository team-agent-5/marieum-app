import 'package:audio_session/audio_session.dart';

// A named adapter boundary supports dependency injection and mocktail.
// ignore: one_member_abstracts
abstract interface class VoiceAudioSession {
  Future<void> configure();
}

class PlatformVoiceAudioSession implements VoiceAudioSession {
  @override
  Future<void> configure() async {
    final session = await AudioSession.instance;
    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
      ),
    );
  }
}
