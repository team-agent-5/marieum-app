import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/quick_phrase.dart';
import 'package:marieum_app/features/quick_phrase/domain/repositories/quick_phrase_repository.dart';
import 'package:marieum_app/features/quick_phrase/presentation/bloc/quick_phrase_bloc.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements QuickPhraseRepository {}

void main() {
  late _MockRepository repository;
  const added = QuickPhrase(
    id: 'c1',
    text: '창문 열어 주세요',
    icon: QuickPhraseIcon.text,
  );

  setUpAll(() => registerFallbackValue(defaultQuickPhrases.first));

  setUp(() {
    repository = _MockRepository();
    when(() => repository.load()).thenReturn(defaultQuickPhrases);
    when(() => repository.recordUse(any())).thenAnswer((_) async {});
  });

  group(QuickPhraseBloc, () {
    test('starts with stored phrases', () {
      expect(
        QuickPhraseBloc(repository).state,
        const QuickPhraseState(phrases: defaultQuickPhrases),
      );
    });

    blocTest<QuickPhraseBloc, QuickPhraseState>(
      'records use without changing state',
      build: () => QuickPhraseBloc(repository),
      act: (bloc) => bloc.add(QuickPhraseUsed(defaultQuickPhrases[2])),
      expect: () => <QuickPhraseState>[],
      verify: (_) =>
          verify(() => repository.recordUse(defaultQuickPhrases[2])).called(1),
    );

    blocTest<QuickPhraseBloc, QuickPhraseState>(
      'emits saving then the new list when a phrase is added',
      build: () {
        when(
          () => repository.add('창문 열어 주세요'),
        ).thenAnswer(
          (_) async => const Success([...defaultQuickPhrases, added]),
        );
        return QuickPhraseBloc(repository);
      },
      act: (bloc) => bloc.add(const QuickPhraseAdded('창문 열어 주세요')),
      expect: () => const [
        QuickPhraseState(
          phrases: defaultQuickPhrases,
          status: QuickPhraseStatus.saving,
        ),
        QuickPhraseState(
          phrases: [...defaultQuickPhrases, added],
          status: QuickPhraseStatus.saved,
        ),
      ],
    );

    blocTest<QuickPhraseBloc, QuickPhraseState>(
      'keeps the list and exposes the failure when removal is refused',
      build: () {
        when(() => repository.remove('preset-1')).thenAnswer(
          (_) async => const FailureResult(ValidationFailure(fieldErrors: {})),
        );
        return QuickPhraseBloc(repository);
      },
      act: (bloc) => bloc.add(const QuickPhraseRemoved('preset-1')),
      expect: () => [
        const QuickPhraseState(
          phrases: defaultQuickPhrases,
          status: QuickPhraseStatus.saving,
        ),
        isA<QuickPhraseState>()
            .having((s) => s.status, 'status', QuickPhraseStatus.failure)
            .having((s) => s.phrases, 'phrases', defaultQuickPhrases),
      ],
    );
  });
}
