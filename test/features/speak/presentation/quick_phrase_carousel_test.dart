import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/quick_phrase.dart';
import 'package:marieum_app/features/quick_phrase/presentation/bloc/quick_phrase_bloc.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/presentation/widgets/quick_phrase_carousel.dart';
import 'package:mocktail/mocktail.dart';

class _MockQuickPhraseBloc extends MockBloc<QuickPhraseEvent, QuickPhraseState>
    implements QuickPhraseBloc {}

void main() {
  late _MockQuickPhraseBloc bloc;
  PlaybackRequest? played;

  setUp(() {
    played = null;
    bloc = _MockQuickPhraseBloc();
    whenListen(
      bloc,
      const Stream<QuickPhraseState>.empty(),
      initialState: const QuickPhraseState(phrases: defaultQuickPhrases),
    );
  });

  setUpAll(
    () => registerFallbackValue(QuickPhraseUsed(defaultQuickPhrases.first)),
  );

  Future<void> pump(
    WidgetTester tester, {
    bool enabled = true,
    bool reduceMotion = false,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(18),
              child: QuickPhraseCarousel(enabled: enabled),
            ),
          ),
        ),
        GoRoute(
          path: '/speak/playback',
          builder: (_, state) {
            played = state.extra! as PlaybackRequest;
            return const SizedBox.shrink();
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: BlocProvider<QuickPhraseBloc>.value(
          value: bloc,
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
  }

  Color hintColor(WidgetTester tester) =>
      tester.widget<Text>(find.text('옆으로 넘겨 더 보기')).style!.color!;

  group(QuickPhraseCarousel, () {
    testWidgets('plays the tapped phrase immediately and records its use', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('물 주세요'));
      await tester.pumpAndSettle();
      expect(played?.text, '물 주세요');
      expect(played?.origin, PlaybackOrigin.quickPhrase);
      verify(
        () => bloc.add(QuickPhraseUsed(defaultQuickPhrases.first)),
      ).called(1);
    });

    testWidgets('ignores taps while disabled', (tester) async {
      await pump(tester, enabled: false);
      await tester.tap(find.text('물 주세요'));
      await tester.pumpAndSettle();
      expect(played, isNull);
      verifyNever(() => bloc.add(any()));
    });

    testWidgets('shows the swipe hint once after seven idle seconds', (
      tester,
    ) async {
      await pump(tester);
      await tester.pump(const Duration(seconds: 6));
      expect(hintColor(tester), AppTokens.ink3);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(hintColor(tester), AppTokens.primaryStrong);
      await tester.pump(const Duration(seconds: 2));
      expect(hintColor(tester), AppTokens.ink3);

      await tester.pump(const Duration(seconds: 40));
      expect(hintColor(tester), AppTokens.ink3);
    });

    testWidgets('waits thirty seconds before hinting again after a touch', (
      tester,
    ) async {
      await pump(tester);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      // A touch re-arms the 7s wait, but the hint stays within the 30s gap.
      await tester.pump(const Duration(seconds: 27));
      expect(hintColor(tester), AppTokens.ink3);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 100));
      expect(hintColor(tester), AppTokens.primaryStrong);
      await tester.pumpAndSettle();
    });

    testWidgets('restarts the idle wait when the screen is touched', (
      tester,
    ) async {
      await pump(tester);
      await tester.pump(const Duration(seconds: 5));
      await tester.tapAt(const Offset(5, 5));
      await tester.pump(const Duration(seconds: 5));
      expect(hintColor(tester), AppTokens.ink3);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 100));
      expect(hintColor(tester), AppTokens.primaryStrong);
      await tester.pumpAndSettle();
    });

    testWidgets('skips the hint when reduce motion is on', (tester) async {
      await pump(tester, reduceMotion: true);
      await tester.pump(const Duration(seconds: 8));
      expect(hintColor(tester), AppTokens.ink3);
    });
  });
}
