import 'dart:async';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/quick_phrase.dart';
import 'package:marieum_app/features/quick_phrase/presentation/bloc/quick_phrase_bloc.dart';
import 'package:marieum_app/features/quick_phrase/presentation/pages/quick_phrase_management_page.dart';
import 'package:mocktail/mocktail.dart';
import '../../helpers/pump_app.dart';

class _MockQuickBloc extends MockBloc<QuickPhraseEvent, QuickPhraseState>
    implements QuickPhraseBloc {}

void main() {
  setUpAll(() => registerFallbackValue(const QuickPhraseAdded('문장')));
  group(QuickPhraseManagementPage, () {
    late _MockQuickBloc bloc;
    setUp(() {
      bloc = _MockQuickBloc();
      when(bloc.close).thenAnswer((_) async {});
    });
    testWidgets('disables every removal at the minimum of three', (
      tester,
    ) async {
      final phrases = defaultQuickPhrases.take(3).toList();
      when(() => bloc.state).thenReturn(QuickPhraseState(phrases: phrases));
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
      final router = await tester.pumpApp(
        initialLocation: '/quick-phrases',
        createQuickPhraseBloc: () => bloc,
      );
      addTearDown(router.dispose);
      for (final phrase in phrases) {
        await tester.tap(
          find.byTooltip('${phrase.text} 빼기'),
          warnIfMissed: false,
        );
      }
      verifyNever(() => bloc.add(any()));
    });
    testWidgets('limits new text to twenty characters and shows a preview', (
      tester,
    ) async {
      when(
        () => bloc.state,
      ).thenReturn(const QuickPhraseState(phrases: defaultQuickPhrases));
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
      final router = await tester.pumpApp(
        initialLocation: '/quick-phrases',
        createQuickPhraseBloc: () => bloc,
      );
      addTearDown(router.dispose);
      await tester.scrollUntilVisible(
        find.text('문장 추가'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('문장 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '가' * 21);
      await tester.pump();
      final text = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .text;
      expect(text, '가' * 20);
      expect(find.text('메인에 이렇게 보여요'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('저장'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('저장'));
      verify(() => bloc.add(QuickPhraseAdded('가' * 20))).called(1);
    });
    testWidgets('returns to the list only after a successful local save', (
      tester,
    ) async {
      final changes = StreamController<QuickPhraseState>();
      whenListen(
        bloc,
        changes.stream,
        initialState: const QuickPhraseState(phrases: defaultQuickPhrases),
      );
      final router = await tester.pumpApp(
        initialLocation: '/quick-phrases',
        createQuickPhraseBloc: () => bloc,
      );
      addTearDown(() async {
        router.dispose();
        await changes.close();
      });
      await tester.scrollUntilVisible(
        find.text('문장 추가'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('문장 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '새 문장');
      await tester.scrollUntilVisible(
        find.text('저장'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('저장'));
      changes.add(
        const QuickPhraseState(
          phrases: defaultQuickPhrases,
          status: QuickPhraseStatus.saving,
        ),
      );
      await tester.pump();
      changes.add(
        const QuickPhraseState(
          phrases: defaultQuickPhrases,
          status: QuickPhraseStatus.saved,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('빠른 문장 관리'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
