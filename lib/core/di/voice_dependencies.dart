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
    ..registerFactory<Recorder>(
      () => Recorder(
        engine: PlatformRecordingEngine(),
        permission: PlatformMicrophonePermission(),
        audioSession: dependencies<VoiceAudioSession>(),
      ),
    )
    ..registerFactory<MicStream>(
      () => MicStream(
        engine: PlatformRecordingEngine(),
        permission: PlatformMicrophonePermission(),
        audioSession: dependencies<VoiceAudioSession>(),
      ),
    )
    ..registerLazySingleton<VoiceHaptics>(
      () => VoiceHaptics(PlatformHapticEngine()),
    );
}
