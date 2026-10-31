import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/haptics/haptics.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/presentation/cubit/playback_cubit.dart';
import 'package:marieum_app/features/speak/presentation/widgets/playback_view.dart';
import 'package:mocktail/mocktail.dart';

class _MockTts extends Mock implements TtsPort {}

class _MockHaptics extends Mock implements VoiceHaptics {}

void main() {
  late _MockTts tts;
  late _MockHaptics haptics;
  late Completer<Result<void>> speaking;

  setUpAll(() => registerFallbackValue(VoiceHaptic.playbackStarted));

  setUp(() {
    tts = _MockTts();
    haptics = _MockHaptics();
    when(() => haptics.trigger(any())).thenAnswer((_) async {});
    when(tts.stop).thenAnswer((_) async => const Success(null));
  });

  Future<PlaybackCubit> pumpView(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    speaking = Completer();
    when(() => tts.speak(any())).thenAnswer((_) => speaking.future);
    final cubit = PlaybackCubit(
      request: const PlaybackRequest(
        text: '물 주세요',
        origin: PlaybackOrigin.quickPhrase,
      ),
      tts: tts,
      haptics: haptics,
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: BlocProvider.value(value: cubit, child: const PlaybackView()),
        ),
      ),
    );
    unawaited(cubit.start());
    await tester.pump();
    return cubit;
  }

  List<double> barHeights(WidgetTester tester) => [
    for (final box in tester.widgetList<Container>(
      find.descendant(
        of: find.byType(ExcludeSemantics).last,
        matching: find.byType(Container),
      ),
    ))
      box.constraints!.maxHeight,
  ];

  group(PlaybackView, () {
    testWidgets('wave moves while speaking', (tester) async {
      await pumpView(tester);
      final first = barHeights(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(barHeights(tester), isNot(equals(first)));
      speaking.complete(const Success(null));
      await tester.pump(PlaybackCubit.returnDelay);
    });

    testWidgets('wave stays still with reduce motion', (tester) async {
      await pumpView(tester, reduceMotion: true);
      final first = barHeights(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(barHeights(tester), first);
      speaking.complete(const Success(null));
      await tester.pump(PlaybackCubit.returnDelay);
    });

    testWidgets('return progress fills during the return delay', (
      tester,
    ) async {
      await pumpView(tester);
      speaking.complete(const Success(null));
      await tester.pump();
      double progress() => tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .value!;
      await tester.pump(const Duration(milliseconds: 500));
      final early = progress();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(progress(), greaterThan(early));
      expect(early, greaterThan(0));
      await tester.pump(PlaybackCubit.returnDelay);
    });
  });
}
