import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/tts/cloud_audio_player.dart';
import 'package:marieum_app/core/tts/cloud_tts_cache.dart';
import 'package:marieum_app/core/tts/cloud_tts_client.dart';
import 'package:marieum_app/core/tts/cloud_tts_port.dart';
import 'package:marieum_app/core/tts/cloud_voice.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:mocktail/mocktail.dart';

class _MockClient extends Mock implements CloudTtsClient {}

class _MockPlayer extends Mock implements CloudAudioPlayer {}

class _MockDevice extends Mock implements TtsPort {}

void main() {
  late Directory temp;
  late _MockClient client;
  late _MockPlayer player;
  late _MockDevice device;
  late CloudTtsPort port;

  setUpAll(() => registerFallbackValue(CloudVoice.female));

  setUp(() {
    temp = Directory.systemTemp.createTempSync('tts_cache');
    addTearDown(() => temp.deleteSync(recursive: true));
    client = _MockClient();
    player = _MockPlayer();
    device = _MockDevice();
    when(() => client.isConfigured).thenReturn(true);
    when(
      () => device.speak(any()),
    ).thenAnswer((_) async => const Success(null));
    when(device.stop).thenAnswer((_) async => const Success(null));
    when(
      () => player.play(
        any(),
        speed: any(named: 'speed'),
        volume: any(named: 'volume'),
      ),
    ).thenAnswer((_) async {});
    when(player.stop).thenAnswer((_) async {});
    port = CloudTtsPort(
      client: client,
      cache: CloudTtsCache(directory: () async => temp),
      player: player,
      device: device,
      warmTexts: () => const ['물 주세요'],
    );
  });

  final wav = Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4]);

  group(CloudTtsPort, () {
    test('plays the cloud voice and reuses the saved file', () async {
      when(
        () => client.synthesize('물 주세요', CloudVoice.male),
      ).thenAnswer((_) async => wav);
      port.voice = CloudVoice.male;
      await pumpEventQueue();

      expect(await port.speak('물 주세요'), isA<Success<void>>());
      await port.speak('물 주세요');
      verify(() => client.synthesize('물 주세요', CloudVoice.male)).called(1);
      final played = verify(
        () => player.play(
          captureAny(),
          speed: any(named: 'speed'),
          volume: any(named: 'volume'),
        ),
      ).captured;
      expect(played, hasLength(2));
      expect(played.first as String, endsWith('.wav'));
      verifyNever(() => device.speak(any()));
    });

    test('uses the device voice when synthesis fails', () async {
      when(
        () => client.synthesize(any(), any()),
      ).thenThrow(const SocketException('offline'));
      expect(await port.speak('아파요'), isA<Success<void>>());
      verify(() => device.speak('아파요')).called(1);
    });

    test('uses the device voice without a key', () async {
      when(() => client.isConfigured).thenReturn(false);
      await port.speak('아파요');
      verify(() => device.speak('아파요')).called(1);
      verifyNever(() => client.synthesize(any(), any()));
    });

    test('stop silences both voices', () async {
      await port.stop();
      verify(player.stop).called(1);
      verify(device.stop).called(1);
    });
  });

  test('cache keys differ by voice and text', () {
    expect(
      CloudTtsCache.keyFor('Aoede', '물'),
      isNot(CloudTtsCache.keyFor('Puck', '물')),
    );
    expect(CloudTtsCache.keyFor('Aoede', '물'), hasLength(16));
  });
}
