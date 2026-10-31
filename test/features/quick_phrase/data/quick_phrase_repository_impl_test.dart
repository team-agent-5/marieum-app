import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/core/storage/sequence_store.dart';
import 'package:marieum_app/features/quick_phrase/data/datasources/preset_data_source.dart';
import 'package:marieum_app/features/quick_phrase/data/datasources/quick_phrase_local_store.dart';
import 'package:marieum_app/features/quick_phrase/data/repositories/quick_phrase_repository_impl.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/preset_receipt.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/quick_phrase.dart';
import 'package:mocktail/mocktail.dart';

class _MemoryPrefs implements PrefsBackend {
  final values = <String, Object>{};
  @override
  String? readString(String key) => values[key] as String?;
  @override
  bool? readBool(String key) => values[key] as bool?;
  @override
  Future<void> writeString(String key, String value) async =>
      values[key] = value;
  @override
  Future<void> writeBool(String key, {required bool value}) async =>
      values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
}

class _MockPresetSource extends Mock implements PresetDataSource {}

void main() {
  late _MemoryPrefs backend;
  late PrefsStore prefs;
  late _MockPresetSource source;
  var ids = 0;

  QuickPhraseRepositoryImpl build() => QuickPhraseRepositoryImpl(
    store: QuickPhraseLocalStore(prefs),
    source: source,
    sequence: SequenceStore(prefs),
    newId: () => 'custom-${++ids}',
  );

  setUp(() {
    backend = _MemoryPrefs();
    prefs = PrefsStore(backend);
    source = _MockPresetSource();
  });

  group(QuickPhraseRepositoryImpl, () {
    test('starts with the ten defaults in server preset order', () {
      final phrases = build().load();
      expect(phrases, hasLength(10));
      expect(
        [for (final phrase in phrases) phrase.presetIndex],
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      );
      expect(phrases.first.text, '물 주세요');
      expect(phrases.last.text, '불러주세요');
    });

    test('persists added phrases across instances', () async {
      final result = await build().add('  따뜻한 물 주세요 ');
      expect(result, isA<Success<List<QuickPhrase>>>());
      final reloaded = build().load();
      expect(reloaded.last.text, '따뜻한 물 주세요');
      expect(reloaded.last.presetIndex, isNull);
      expect(reloaded.last.icon, QuickPhraseIcon.text);
    });

    test('rejects blank, too long and duplicate text', () async {
      final repository = build();
      for (final text in ['   ', '가' * 21, '물 주세요']) {
        expect(
          await repository.add(text),
          isA<FailureResult<List<QuickPhrase>>>().having(
            (result) => result.failure,
            'failure',
            isA<ValidationFailure>(),
          ),
        );
      }
      expect(repository.load(), hasLength(10));
    });

    test('accepts exactly twenty characters', () async {
      expect(await build().add('가' * 20), isA<Success<List<QuickPhrase>>>());
    });

    test('keeps at least three phrases', () async {
      final repository = build();
      for (final phrase in defaultQuickPhrases.take(7)) {
        expect(
          await repository.remove(phrase.id),
          isA<Success<List<QuickPhrase>>>(),
        );
      }
      expect(repository.load(), hasLength(3));
      expect(
        await repository.remove(repository.load().first.id),
        isA<FailureResult<List<QuickPhrase>>>(),
      );
      expect(build().load(), hasLength(3));
    });

    test('falls back to defaults when stored data is unreadable', () {
      backend.values[PrefsKeys.quickPhrases] = '{not json';
      expect(build().load(), defaultQuickPhrases);
    });

    test(
      'records defaults with their preset index and keeps the log id',
      () async {
        when(() => source.usePreset(7)).thenAnswer(
          (_) async => const Success(
            PresetReceipt(logId: '42', finalText: '아파요', presetIndex: 7),
          ),
        );
        await build().recordUse(defaultQuickPhrases[6]);
        verify(() => source.usePreset(7)).called(1);
        expect(SequenceStore(prefs).lastLogId, '42');
      },
    );

    test('does not send user-added phrases to the server', () async {
      final repository = build();
      await repository.add('창문 열어 주세요');
      await repository.recordUse(repository.load().last);
      verifyNever(() => source.usePreset(any()));
    });

    test('swallows logging failures', () async {
      when(
        () => source.usePreset(1),
      ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
      await expectLater(
        build().recordUse(defaultQuickPhrases.first),
        completes,
      );
      expect(SequenceStore(prefs).lastLogId, isNull);
    });
  });
}
