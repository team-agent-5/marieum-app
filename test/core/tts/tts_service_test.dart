import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/voice_audio_session.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/tts/tts_engine.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/core/tts/tts_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockEngine extends Mock implements TtsEngine {}

class _MockSession extends Mock implements VoiceAudioSession {}

void main() {
  group(TtsService, () {
    late _MockEngine engine;
    late _MockSession session;
    late TtsService service;
    setUp(() {
      engine = _MockEngine();
      session = _MockSession();
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
  });
}
