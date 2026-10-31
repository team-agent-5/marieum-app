import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/voice_audio_session.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/tts/tts_engine.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/core/tts/tts_service.dart';
import 'package:marieum_app/core/tts/tts_voice.dart';
import 'package:mocktail/mocktail.dart';

class _MockEngine extends Mock implements TtsEngine {}

class _MockSession extends Mock implements VoiceAudioSession {}

void main() {
  group(TtsService, () {
    late _MockEngine engine;
    late _MockSession session;
    late TtsService service;
    setUpAll(
      () => registerFallbackValue(
        const TtsVoice(
          id: 'test',
          name: 'test',
          locale: 'ko-KR',
          quality: TtsVoiceQuality.normal,
          requiresNetwork: false,
        ),
      ),
    );
    setUp(() {
      engine = _MockEngine();
      session = _MockSession();
      when(engine.koreanVoices).thenAnswer((_) async => []);
      when(() => engine.setVoice(any())).thenAnswer((_) async {});
      when(
        () => engine.isLanguageAvailable('ko-KR'),
      ).thenAnswer((_) async => true);
      when(
        () => engine.configure(
          rate: any(named: 'rate'),
          volume: any(named: 'volume'),
        ),
      ).thenAnswer((_) async {});
      when(() => engine.speak(any())).thenAnswer((_) async {});
      when(() => engine.stop()).thenAnswer((_) async {});
      when(() => session.configure()).thenAnswer((_) async {});
      service = TtsService(
        engine: engine,
        audioSession: session,
        platform: VoicePlatform.ios,
      );
    });
    tearDown(() async {
      await service.dispose();
    });

    test(
      'forwards native playback boundaries instead of speech dispatch',
      () async {
        final completed = Completer<void>();
        late void Function() nativeStart;
        when(
          () => engine.speak(any(), onStarted: any(named: 'onStarted')),
        ).thenAnswer((call) {
          nativeStart = call.namedArguments[#onStarted]! as void Function();
          return completed.future;
        });
        final events = <String>[];
        final speech = service.speakWithPlayback(
          '물 주세요',
          onStarted: () => events.add('start'),
          onEnded: () => events.add('end'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
        nativeStart();
        expect(events, ['start']);
        completed.complete();
        expect(await speech, isA<Success<void>>());
        expect(events, ['start', 'end']);
      },
    );
    test(
      'applies mapping and reconfigures the session after the TTS plugin',
      () async {
        service
          ..rate = TtsRate.fast
          ..volume = TtsVolume.soft;
        expect(await service.speak('물 주세요'), isA<Success<void>>());
        verifyInOrder([
          () => engine.configure(rate: 0.6, volume: 0.5),
          () => session.configure(),
          () => engine.speak('물 주세요'),
        ]);
      },
    );
    test(
      'waits for actual engine completion instead of acknowledging dispatch',
      () async {
        final completion = Completer<void>();
        when(() => engine.speak(any())).thenAnswer((_) => completion.future);
        var finished = false;
        final result = service.speak('물 주세요').then((value) {
          finished = true;
          return value;
        });
        await Future<void>.delayed(Duration.zero);
        expect(finished, isFalse);
        completion.complete();
        expect(await result, isA<Success<void>>());
      },
    );
    test(
      'returns unavailable without attempting speech when Korean is missing',
      () async {
        when(
          () => engine.isLanguageAvailable('ko-KR'),
        ).thenAnswer((_) async => false);
        final result = await service.speak('물 주세요');
        expect(
          result,
          isA<FailureResult<void>>().having(
            (r) => r.failure,
            'failure',
            isA<TtsUnavailableFailure>(),
          ),
        );
        verifyNever(() => engine.speak(any()));
      },
    );
    test(
      'stopping while availability is pending prevents a late speech start',
      () async {
        final availability = Completer<bool>();
        when(
          () => engine.isLanguageAvailable('ko-KR'),
        ).thenAnswer((_) => availability.future);
        final speaking = service.speak('물 주세요');
        await service.stop();
        expect(await speaking, isA<FailureResult<void>>());
        availability.complete(true);
        await Future<void>.delayed(Duration.zero);
        verifyNever(() => engine.speak(any()));
      },
    );
    test(
      'reuses successful Korean availability for subsequent speech',
      () async {
        expect(await service.isKoreanAvailable(), isTrue);
        expect(await service.speak('첫 문장'), isA<Success<void>>());
        expect(await service.speak('다음 문장'), isA<Success<void>>());
        verify(() => engine.isLanguageAvailable('ko-KR')).called(1);
      },
    );

    test('retries unavailable Korean and caches a later success', () async {
      var attempts = 0;
      when(
        () => engine.isLanguageAvailable('ko-KR'),
      ).thenAnswer((_) async => ++attempts > 1);
      expect(await service.speak('첫 문장'), isA<FailureResult<void>>());
      expect(await service.speak('재시도'), isA<Success<void>>());
      expect(await service.speak('다음 문장'), isA<Success<void>>());
      verify(() => engine.isLanguageAvailable('ko-KR')).called(2);
    });

    test('retries a failed availability request', () async {
      var attempts = 0;
      when(() => engine.isLanguageAvailable('ko-KR')).thenAnswer((_) async {
        if (++attempts == 1) throw Exception('engine not ready');
        return true;
      });
      expect(await service.speak('첫 문장'), isA<FailureResult<void>>());
      expect(await service.speak('재시도'), isA<Success<void>>());
      expect(await service.speak('다음 문장'), isA<Success<void>>());
      verify(() => engine.isLanguageAvailable('ko-KR')).called(2);
    });

    test('coalesces concurrent Korean availability checks', () async {
      final pending = Completer<bool>();
      when(
        () => engine.isLanguageAvailable('ko-KR'),
      ).thenAnswer((_) => pending.future);
      final first = service.isKoreanAvailable();
      final second = service.isKoreanAvailable();
      pending.complete(true);
      expect(await first, isTrue);
      expect(await second, isTrue);
      verify(() => engine.isLanguageAvailable('ko-KR')).called(1);
    });

    test('rechecks Korean availability after a speech failure', () async {
      var attempts = 0;
      when(() => engine.speak(any())).thenAnswer((_) async {
        if (++attempts == 1) throw Exception('voice became unavailable');
      });
      expect(await service.speak('첫 문장'), isA<FailureResult<void>>());
      expect(await service.speak('재시도'), isA<Success<void>>());
      expect(await service.speak('다음 문장'), isA<Success<void>>());
      verify(() => engine.isLanguageAvailable('ko-KR')).called(2);
    });

    test(
      'rejects overlapping speech without replacing the active utterance',
      () async {
        final completion = Completer<void>();
        when(() => engine.speak(any())).thenAnswer((_) => completion.future);
        final first = service.speak('첫 문장');
        expect(await service.speak('두 번째'), isA<FailureResult<void>>());
        completion.complete();
        expect(await first, isA<Success<void>>());
      },
    );
    group('voice selection', () {
      TtsVoice voice(
        String id,
        TtsVoiceQuality quality, {
        bool network = false,
      }) => TtsVoice(
        id: id,
        name: id,
        locale: 'ko-KR',
        quality: quality,
        requiresNetwork: network,
      );

      for (final quality in TtsVoiceQuality.values) {
        test('prefers $quality over every lower offline quality', () async {
          final candidates = [
            for (final item in TtsVoiceQuality.values.reversed)
              if (item.index >= quality.index) voice(item.name, item),
          ];
          when(engine.koreanVoices).thenAnswer((_) async => candidates);
          await service.availableVoices();
          expect(service.currentVoice?.quality, quality);
        });
      }

      test(
        'places network voices after offline voices even at higher quality',
        () async {
          final online = voice('온라인', TtsVoiceQuality.premium, network: true);
          final offline = voice('오프라인', TtsVoiceQuality.normal);
          when(engine.koreanVoices).thenAnswer((_) async => [online, offline]);
          await service.speak('물 주세요');
          expect(service.currentVoice, offline);
          verify(() => engine.setVoice(offline)).called(1);
        },
      );

      test('prefers an offline voice within the same quality', () async {
        final online = voice('온라인', TtsVoiceQuality.enhanced, network: true);
        final offline = voice('오프라인', TtsVoiceQuality.enhanced);
        when(engine.koreanVoices).thenAnswer((_) async => [online, offline]);
        await service.availableVoices();
        expect(service.currentVoice, offline);
      });

      test(
        'honors a user choice including a network voice before auto ranking',
        () async {
          final preferred = voice('선택', TtsVoiceQuality.normal, network: true);
          when(engine.koreanVoices).thenAnswer(
            (_) async => [
              voice('자동', TtsVoiceQuality.premium),
              preferred,
            ],
          );
          await service.selectVoice(preferred.id);
          verifyNever(engine.koreanVoices);
          await service.speak('물 주세요');
          expect(service.currentVoice, preferred);
          verify(() => engine.setVoice(preferred)).called(1);
        },
      );

      test(
        'falls back to auto when the persisted voice has been removed',
        () async {
          final auto = voice('자동', TtsVoiceQuality.enhanced);
          when(engine.koreanVoices).thenAnswer((_) async => [auto]);
          await service.selectVoice('삭제된 음성');
          await service.speak('물 주세요');
          expect(service.currentVoice, auto);
          verify(() => engine.setVoice(auto)).called(1);
        },
      );

      test(
        'caches the list and updates selection '
        'only when the choice changes',
        () async {
          final auto = voice('자동', TtsVoiceQuality.premium);
          final preferred = voice('선택', TtsVoiceQuality.normal);
          when(engine.koreanVoices).thenAnswer((_) async => [auto, preferred]);
          await Future.wait([
            service.availableVoices(),
            service.availableVoices(),
          ]);
          await service.selectVoice(preferred.id);
          expect(service.currentVoice, preferred);
          await service.speak('첫 재생');
          await service.selectVoice(null);
          await service.speak('둘째 재생');
          expect(service.currentVoice, auto);
          verify(engine.koreanVoices).called(1);
          verifyInOrder([
            () => engine.configure(rate: 0.5, volume: 0.8),
            () => engine.setVoice(preferred),
            () => engine.speak('첫 재생'),
            () => engine.configure(rate: 0.5, volume: 0.8),
            () => engine.setVoice(auto),
            () => engine.speak('둘째 재생'),
          ]);
        },
      );

      test('continues speech when setting the selected voice fails', () async {
        when(
          engine.koreanVoices,
        ).thenAnswer((_) async => [voice('목소리', TtsVoiceQuality.high)]);
        when(
          () => engine.setVoice(any()),
        ).thenThrow(Exception('voice unavailable'));
        expect(await service.speak('물 주세요'), isA<Success<void>>());
        verify(() => engine.speak('물 주세요')).called(1);
      });

      test(
        'uses the default voice when enumeration fails or returns nothing',
        () async {
          when(engine.koreanVoices).thenThrow(Exception('unsupported'));
          expect(await service.speak('물 주세요'), isA<Success<void>>());
          expect(service.currentVoice, isNull);
          verifyNever(() => engine.setVoice(any()));
        },
      );

      test(
        'ignores a late voice list after stop without starting speech',
        () async {
          final pending = Completer<List<TtsVoice>>();
          when(engine.koreanVoices).thenAnswer((_) => pending.future);
          final speaking = service.speak('물 주세요');
          await Future<void>.delayed(Duration.zero);
          await service.stop();
          pending.complete([voice('목소리', TtsVoiceQuality.premium)]);
          await speaking;
          await Future<void>.delayed(Duration.zero);
          verifyNever(() => engine.speak(any()));
          verifyNever(() => engine.setVoice(any()));
        },
      );
    });
  });
}
