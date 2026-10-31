import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/tts/tts_engine.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/core/tts/tts_voice.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlugin extends Mock implements FlutterTts {}

void main() {
  group(FlutterTtsEngine, () {
    late _MockPlugin plugin;
    late FlutterTtsEngine engine;
    late void Function() completed;
    setUpAll(() {
      registerFallbackValue(() {});
    });
    setUp(() {
      plugin = _MockPlugin();
      when(() => plugin.setCompletionHandler(any())).thenAnswer((call) {
        completed = call.positionalArguments.first as void Function();
      });
      when(() => plugin.speak(any())).thenAnswer((_) async => 1);
      when(() => plugin.stop()).thenAnswer((_) async => 1);
      when(() => plugin.awaitSpeakCompletion(false)).thenAnswer((_) async => 1);
      when(
        () => plugin.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playAndRecord,
          [
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          ],
        ),
      ).thenAnswer((_) async => 1);
      when(() => plugin.setLanguage('ko-KR')).thenAnswer((_) async => 1);
      when(() => plugin.setSpeechRate(0.5)).thenAnswer((_) async => 1);
      when(() => plugin.setVolume(0.8)).thenAnswer((_) async => 1);
      engine = FlutterTtsEngine(platform: VoicePlatform.ios, plugin: plugin);
    });
    test(
      'waits for the native completion callback after dispatch',
      () async {
        var finished = false;
        final speaking = engine.speak('안녕하세요').then((_) {
          finished = true;
        });
        await Future<void>.delayed(Duration.zero);
        expect(finished, isFalse);
        completed();
        await speaking;
        expect(finished, isTrue);
      },
    );
    test(
      'stopping settles the pending speech without requiring a native callback',
      () async {
        final speaking = engine.speak('안녕하세요');
        final failure = expectLater(speaking, throwsA(isA<TtsFailure>()));
        await engine.stop();
        await failure;
      },
    );
    test(
      'matches speaker and Bluetooth audio session options',
      () async {
        await engine.configure(rate: 0.5, volume: 0.8);
        verify(
          () => plugin.setIosAudioCategory(
            IosTextToSpeechAudioCategory.playAndRecord,
            [
              IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
              IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            ],
          ),
        ).called(1);
        verify(() => plugin.setLanguage('ko-KR')).called(1);
      },
    );
    group('koreanVoices', () {
      test(
        'parses iOS quality and identifiers and filters non-Korean voices',
        () async {
          when(() => plugin.getVoices).thenAnswer(
            (_) async => [
              {
                'name': '프리미엄',
                'locale': 'ko-KR',
                'quality': 'premium',
                'identifier': 'premium-id',
              },
              {'name': '향상', 'locale': 'ko-KR', 'quality': 'enhanced'},
              {'name': '기본', 'locale': 'ko-KR', 'quality': 'default'},
              {'name': 'English', 'locale': 'en-US', 'quality': 'premium'},
            ],
          );
          final voices = await engine.koreanVoices();
          expect(voices.map((v) => v.quality), [
            TtsVoiceQuality.premium,
            TtsVoiceQuality.enhanced,
            TtsVoiceQuality.normal,
          ]);
          expect(voices.map((v) => v.id), ['premium-id', '향상', '기본']);
          expect(voices.every((v) => !v.requiresNetwork), isTrue);
        },
      );

      test(
        'ignores malformed entries and tolerates absent optional keys',
        () async {
          when(() => plugin.getVoices).thenAnswer(
            (_) async => [
              null,
              42,
              'ko-KR',
              <String, Object?>{},
              {'name': 3, 'locale': 'ko-KR'},
              {'name': '이름', 'locale': false},
              {'name': '', 'locale': 'ko-KR'},
              {
                'name': '목소리',
                'locale': 'KO-kr',
                'quality': <String, Object?>{},
                'identifier': 3,
                'network_required': <Object?>[],
                'features': 7,
                'unexpected': true,
              },
              {'name': '다른 목소리', 'locale': 'ko-KR'},
            ],
          );
          final voices = await engine.koreanVoices();
          expect(voices.map((v) => v.id), ['목소리', '다른 목소리']);
          expect(
            voices.every((v) => v.quality == TtsVoiceQuality.unknown),
            isTrue,
          );
          expect(voices.every((v) => !v.requiresNetwork), isTrue);
        },
      );

      for (final value in <Object?>[
        null,
        1,
        'voices',
        {'name': '목소리'},
      ]) {
        test('returns no voices for a non-list result $value', () async {
          when(() => plugin.getVoices).thenAnswer((_) async => value);
          expect(await engine.koreanVoices(), isEmpty);
        });
      }

      test(
        'parses Android numeric quality boundaries and network flags',
        () async {
          engine = FlutterTtsEngine(
            platform: VoicePlatform.android,
            plugin: plugin,
          );
          when(() => plugin.getVoices).thenAnswer(
            (_) async => [
              {
                'name': '500',
                'locale': 'ko-KR',
                'quality': 500,
                'network_required': true,
              },
              {
                'name': '499',
                'locale': 'ko-KR',
                'quality': 499,
                'network_required': '1',
              },
              {
                'name': '300',
                'locale': 'ko-KR',
                'quality': 300,
                'network_required': 1,
              },
              {
                'name': '299',
                'locale': 'ko-KR',
                'quality': 299,
                'features': ['networkTts', 4],
              },
              {
                'name': '문자열',
                'locale': 'ko-KR',
                'quality': '500',
                'features': 'embeddedTts\tnetworkTts',
              },
              {
                'name': '오프라인',
                'locale': 'ko-KR',
                'quality': 300,
                'network_required': '0',
                'features': 'embeddedTts',
              },
            ],
          );
          final voices = await engine.koreanVoices();
          expect(voices.map((v) => v.quality), [
            TtsVoiceQuality.high,
            TtsVoiceQuality.normal,
            TtsVoiceQuality.normal,
            TtsVoiceQuality.unknown,
            TtsVoiceQuality.high,
            TtsVoiceQuality.normal,
          ]);
          expect(voices.map((v) => v.requiresNetwork), [
            true,
            true,
            true,
            true,
            true,
            false,
          ]);
        },
      );

      test(
        'supports Android quality strings returned by the installed plugin',
        () async {
          engine = FlutterTtsEngine(
            platform: VoicePlatform.android,
            plugin: plugin,
          );
          when(() => plugin.getVoices).thenAnswer(
            (_) async => [
              for (final quality in [
                'very high',
                'high',
                'normal',
                'low',
                'very low',
                'unknown',
              ])
                {'name': quality, 'locale': 'ko-KR', 'quality': quality},
            ],
          );
          expect((await engine.koreanVoices()).map((v) => v.quality), [
            TtsVoiceQuality.high,
            TtsVoiceQuality.normal,
            TtsVoiceQuality.normal,
            TtsVoiceQuality.unknown,
            TtsVoiceQuality.unknown,
            TtsVoiceQuality.unknown,
          ]);
        },
      );
    });

    group('setVoice', () {
      const voice = TtsVoice(
        id: 'id',
        name: '목소리',
        locale: 'ko-KR',
        quality: TtsVoiceQuality.enhanced,
        requiresNetwork: false,
      );
      test('passes only the requested name and locale to the plugin', () async {
        when(() => plugin.setVoice(any())).thenAnswer((_) async => 1);
        await engine.setVoice(voice);
        verify(
          () => plugin.setVoice({'name': '목소리', 'locale': 'ko-KR'}),
        ).called(1);
      });
      test(
        'reports native rejection so the service can use its default voice',
        () async {
          when(() => plugin.setVoice(any())).thenAnswer((_) async => 0);
          await expectLater(engine.setVoice(voice), throwsA(isA<TtsFailure>()));
        },
      );
    });
  });
}
