import 'dart:io';

import 'package:duplex_audio/duplex_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/tts/cloud_tts_port.dart';
import 'package:marieum_app/core/tts/cloud_voice.dart';
import 'package:marieum_app/core/tts/duplex_tts_port.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/core/tts/tts_service.dart';
import 'package:marieum_app/core/tts/tts_voice.dart';
import 'package:mocktail/mocktail.dart';

class _MockAudio extends Mock implements DuplexAudio {}

class _MockCloud extends Mock implements CloudTtsPort {}

class _MockDevice extends Mock implements TtsService {}

void main() {
  group(DuplexTtsPort, () {
    late _MockAudio audio;
    late _MockCloud cloud;
    late _MockDevice device;
    late DuplexTtsPort port;
    late List<String> events;

    setUp(() {
      audio = _MockAudio();
      cloud = _MockCloud();
      device = _MockDevice();
      events = [];
      port = DuplexTtsPort(cloud: cloud, device: device, audio: audio);
      when(() => cloud.enabled).thenReturn(true);
      when(() => cloud.voice).thenReturn(CloudVoice.female);
      when(() => cloud.rate).thenReturn(TtsRate.normal);
      when(() => cloud.volume).thenReturn(TtsVolume.normal);
      when(() => device.rate).thenReturn(TtsRate.slow);
      when(() => device.volume).thenReturn(TtsVolume.loud);
      when(() => device.currentVoice).thenReturn(
        const TtsVoice(
          id: 'yuna',
          name: 'Yuna',
          locale: 'ko-KR',
          quality: TtsVoiceQuality.premium,
          requiresNetwork: false,
        ),
      );
    });

    Future<Result<void>> speak() => port.speakWithPlayback(
      '물 좀 주세요',
      onStarted: () => events.add('started'),
      onEnded: () => events.add('ended'),
    );

    test('plays a cached cloud voice through the shared engine', () async {
      when(
        () => cloud.cachedAudio('물 좀 주세요'),
      ).thenAnswer((_) async => File('/tmp/voice.wav'));
      when(
        () => audio.playFile(
          '/tmp/voice.wav',
          rate: 1,
          volume: 0.8,
          onStarted: any(named: 'onStarted'),
        ),
      ).thenAnswer((call) async {
        (call.namedArguments[#onStarted]! as void Function())();
        return true;
      });
      expect(await speak(), isA<Success<void>>());
      expect(events, ['started', 'ended']);
    });

    test(
      'speaks with the chosen device voice when nothing is cached',
      () async {
        when(() => cloud.cachedAudio(any())).thenAnswer((_) async => null);
        when(
          () => audio.speak(
            '물 좀 주세요',
            voiceId: 'yuna',
            rate: 0.38,
            volume: 1,
            onStarted: any(named: 'onStarted'),
          ),
        ).thenAnswer((_) async => false);
        expect(await speak(), isA<FailureResult<void>>());
        expect(events, isEmpty);
      },
    );
  });
}
