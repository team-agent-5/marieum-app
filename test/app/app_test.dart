import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/app/marieum_app.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_tab_bar.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/domain/entities/speak_mode.dart';

import '../helpers/pump_app.dart';

void main() {
  group(MarieumApp, () {
    group('navigation', () {
      testWidgets(
        'switches between three tabs and returns to the speaking tab',
        (tester) async {
          final router = await tester.pumpApp();
          addTearDown(router.dispose);
          for (final entry in {
            '요청': '/history',
            '설정': '/settings',
            '말하기': '/speak',
          }.entries) {
            await tester.tap(
              find.descendant(
                of: find.byType(AdaptiveTabBar),
                matching: find.text(entry.key),
              ),
            );
            await tester.pumpAndSettle();
            expect(router.state.uri.path, entry.value);
          }
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'opens drawer details outside the tabs and restores the shell on back',
        (tester) async {
          final router = await tester.pumpApp();
          addTearDown(router.dispose);
          await tester.tap(find.byTooltip('메뉴 열기'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('빠른 문장 관리'));
          await tester.pumpAndSettle();
          expect(
            router.state.uri.path,
            '/quick-phrases',
          );
          expect(find.byType(AdaptiveTabBar), findsNothing);
          await tester.tap(find.byTooltip('뒤로'));
          await tester.pumpAndSettle();
          expect(router.state.uri.path, '/speak');
          expect(find.byType(AdaptiveTabBar), findsOneWidget);
        },
      );

      testWidgets('opens the onboarding review with its review flag', (
        tester,
      ) async {
        final router = await tester.pumpApp();
        addTearDown(router.dispose);
        await tester.tap(find.byTooltip('메뉴 열기'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('사용 방법 다시 보기'));
        await tester.pumpAndSettle();
        expect(
          router.state.uri.toString(),
          '/onboarding?review=1',
        );
      });

      for (final location in [
        '/unknown',
        '/speak/utterance',
        '/speak/playback',
      ]) {
        testWidgets('sends unsupported entry $location to the speaking tab', (
          tester,
        ) async {
          final router = await tester.pumpApp(initialLocation: location);
          addTearDown(router.dispose);
          expect(router.state.uri.path, '/speak');
          expect(find.byType(AdaptiveTabBar), findsOneWidget);
        });
      }

      testWidgets(
        'replaces utterance with playback and returns to the origin',
        (tester) async {
          final router = await tester.pumpApp();
          addTearDown(router.dispose);
          unawaited(
            router.push<void>('/speak/utterance', extra: SpeakMode.precise),
          );
          await tester.pumpAndSettle();
          expect(find.byType(AdaptiveTabBar), findsNothing);
          unawaited(
            router.pushReplacement<void>(
              '/speak/playback',
              extra: const PlaybackRequest(
                text: '물 주세요',
                origin: PlaybackOrigin.utterance,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('음성 재생'), findsOneWidget);
          router.pop();
          await tester.pumpAndSettle();
          expect(router.state.uri.path, '/speak');
        },
      );
    });

    group('configuration', () {
      testWidgets(
        'uses native iOS tab controls and switches to history',
        (tester) async {
          final router = await tester.pumpApp();
          addTearDown(router.dispose);
          expect(find.byType(CupertinoTabBar), findsOneWidget);
          await tester.tap(find.text('요청'));
          await tester.pumpAndSettle();
          expect(router.state.uri.path, '/history');
          expect(tester.takeException(), isNull);
        },
        variant: const TargetPlatformVariant({TargetPlatform.iOS}),
      );
    });
  });
}
