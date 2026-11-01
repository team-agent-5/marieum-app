import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:marieum_app/core/audio/mic_stream.dart';
import 'package:marieum_app/core/audio/recorder.dart';
import 'package:marieum_app/core/audio/recording_engine.dart';
import 'package:marieum_app/core/audio/voice_audio_session.dart';
import 'package:marieum_app/core/haptics/haptics.dart';
import 'package:marieum_app/core/tts/cloud_audio_player.dart';
import 'package:marieum_app/core/tts/cloud_tts_cache.dart';
import 'package:marieum_app/core/tts/cloud_tts_client.dart';
import 'package:marieum_app/core/tts/cloud_tts_port.dart';
import 'package:marieum_app/core/tts/duplex_tts_port.dart';
import 'package:marieum_app/core/tts/live_tts_port.dart';
import 'package:marieum_app/core/tts/tts_engine.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/core/tts/tts_service.dart';

void registerVoiceDependencies(
  GetIt dependencies, {
  required String cloudApiKey,
  required List<String> Function() warmTexts,
}) {
  final platform = defaultTargetPlatform == TargetPlatform.iOS
      ? VoicePlatform.ios
      : VoicePlatform.android;
  dependencies
    ..registerLazySingleton<VoiceAudioSession>(PlatformVoiceAudioSession.new)
    ..registerLazySingleton<TtsService>(
      () => TtsService(
        engine: FlutterTtsEngine(platform: platform),
        audioSession: dependencies<VoiceAudioSession>(),
        platform: platform,
      ),
      dispose: (service) => service.dispose(),
    )
    ..registerLazySingleton<CloudTtsPort>(
      () => CloudTtsPort(
        client: CloudTtsClient(apiKey: cloudApiKey),
        cache: CloudTtsCache(),
        player: JustAudioCloudPlayer(),
        device: dependencies<TtsService>(),
        warmTexts: warmTexts,
      ),
    )
    ..registerLazySingleton<TtsPort>(() => dependencies<CloudTtsPort>())
    // Live mode listens while it speaks. On iOS both go through one engine
    // so echo cancellation knows the app's voice.
    ..registerLazySingleton<PlaybackTtsPort>(
      () => platform == VoicePlatform.ios
          ? DuplexTtsPort(
              cloud: dependencies<CloudTtsPort>(),
              device: dependencies<TtsService>(),
            )
          : LiveTtsPort(dependencies<CloudTtsPort>()),
    )
    ..registerFactory<Recorder>(
      () => Recorder(
        engine: PlatformRecordingEngine(),
        permission: PlatformMicrophonePermission(),
        audioSession: dependencies<VoiceAudioSession>(),
      ),
    )
    ..registerFactory<MicStream>(
      () => MicStream(
        engine: platform == VoicePlatform.ios
            ? DuplexRecordingEngine()
            : PlatformRecordingEngine(),
        permission: PlatformMicrophonePermission(),
        audioSession: dependencies<VoiceAudioSession>(),
        // Android mutes what it sends while the app speaks, so it keeps the
        // recognition source; the communication source that echo
        // cancellation needs blurs weak consonants.
        echoCancel: platform == VoicePlatform.ios,
      ),
    )
    ..registerLazySingleton<VoiceHaptics>(
      () => VoiceHaptics(PlatformHapticEngine()),
    );
}
