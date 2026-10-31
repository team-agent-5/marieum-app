import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/haptics/haptics.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/presentation/cubit/playback_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockTts extends Mock implements TtsPort {}

class _MockHaptics extends Mock implements VoiceHaptics {}

void main() {
  late _MockTts tts;
  late _MockHaptics haptics;
  const request = PlaybackRequest(
    text: '물 주세요',
    origin: PlaybackOrigin.quickPhrase,
  );

  setUpAll(() => registerFallbackValue(VoiceHaptic.playbackStarted));

  setUp(() {
    tts = _MockTts();
    haptics = _MockHaptics();
    when(() => haptics.trigger(any())).thenAnswer((_) async {});
    when(tts.stop).thenAnswer((_) async => const Success(null));
  });

  PlaybackCubit build() =>
      PlaybackCubit(request: request, tts: tts, haptics: haptics);

  group(PlaybackCubit, () {
    blocTest<PlaybackCubit, PlaybackState>(
      'plays, completes, then closes two seconds later',
      build: () {
        when(
          () => tts.speak('물 주세요'),
        ).thenAnswer((_) async => const Success(null));
        return build();
      },
      act: (cubit) => cubit.start(),
      wait: const Duration(milliseconds: 2100),
      expect: () => const [
        PlaybackState(text: '물 주세요', status: PlaybackStatus.playing),
        PlaybackState(text: '물 주세요', status: PlaybackStatus.completed),
        PlaybackState(text: '물 주세요', status: PlaybackStatus.closed),
      ],
    );

    blocTest<PlaybackCubit, PlaybackState>(
      'keeps the text on screen when speech fails',
      build: () {
        when(() => tts.speak(any())).thenAnswer(
          (_) async => const FailureResult(TtsUnavailableFailure()),
        );
        return build();
      },
      act: (cubit) => cubit.start(),
      expect: () => const [
        PlaybackState(text: '물 주세요', status: PlaybackStatus.playing),
        PlaybackState(
          text: '물 주세요',
          status: PlaybackStatus.failed,
          failure: TtsUnavailableFailure(),
        ),
      ],
    );

    blocTest<PlaybackCubit, PlaybackState>(
      'stops speech and ignores the late completion',
      build: () {
        final speaking = Completer<Result<void>>();
        when(() => tts.speak(any())).thenAnswer((_) => speaking.future);
        when(tts.stop).thenAnswer((_) async {
          speaking.complete(const Success(null));
          return const Success(null);
        });
        return build();
      },
      act: (cubit) async {
        unawaited(cubit.start());
        await Future<void>.delayed(Duration.zero);
        await cubit.stop();
      },
      wait: const Duration(milliseconds: 2100),
      expect: () => const [
        PlaybackState(text: '물 주세요', status: PlaybackStatus.playing),
        PlaybackState(text: '물 주세요', status: PlaybackStatus.closed),
      ],
      verify: (_) => verify(tts.stop).called(1),
    );
  });
}
