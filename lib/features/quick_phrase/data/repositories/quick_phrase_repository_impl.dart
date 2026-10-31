import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/storage/sequence_store.dart';
import 'package:marieum_app/features/quick_phrase/data/datasources/preset_data_source.dart';
import 'package:marieum_app/features/quick_phrase/data/datasources/quick_phrase_local_store.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/quick_phrase.dart';
import 'package:marieum_app/features/quick_phrase/domain/repositories/quick_phrase_repository.dart';
import 'package:uuid/uuid.dart';

class QuickPhraseRepositoryImpl implements QuickPhraseRepository {
  QuickPhraseRepositoryImpl({
    required this._store,
    required this._source,
    required this._sequence,
    String Function()? newId,
  }) : _newId = newId ?? const Uuid().v4;

  final QuickPhraseLocalStore _store;
  final PresetDataSource _source;
  final SequenceStore _sequence;
  final String Function() _newId;
  List<QuickPhrase>? _cache;

  @override
  List<QuickPhrase> load() => _cache ??= _store.read() ?? defaultQuickPhrases;

  @override
  Future<Result<List<QuickPhrase>>> add(String text) async {
    final value = text.trim();
    final current = load();
    final error = switch (value) {
      '' => '문장을 입력해 주세요.',
      _ when value.runes.length > QuickPhraseRules.maxLength =>
        '${QuickPhraseRules.maxLength}자 이내로 적어 주세요.',
      _ when current.any((phrase) => phrase.text == value) => '이미 있는 문장이에요.',
      _ when current.length >= QuickPhraseRules.maxCount =>
        '빠른 문장은 ${QuickPhraseRules.maxCount}개까지 둘 수 있어요.',
      _ => null,
    };
    if (error != null) {
      return FailureResult(
        ValidationFailure(
          fieldErrors: {
            'text': [error],
          },
          message: error,
        ),
      );
    }
    return _save([
      ...current,
      QuickPhrase(id: _newId(), text: value, icon: QuickPhraseIcon.text),
    ]);
  }

  @override
  Future<Result<List<QuickPhrase>>> remove(String id) async {
    final current = load();
    if (current.length <= QuickPhraseRules.minCount) {
      return const FailureResult(
        ValidationFailure(
          fieldErrors: {},
          message: '빠른 문장은 ${QuickPhraseRules.minCount}개 이상 남겨 주세요.',
        ),
      );
    }
    return _save([
      for (final phrase in current)
        if (phrase.id != id) phrase,
    ]);
  }

  Future<Result<List<QuickPhrase>>> _save(List<QuickPhrase> next) async {
    try {
      await _store.write(next);
    } on Object catch (error) {
      return FailureResult(
        error is Failure ? error : StorageFailure(cause: error),
      );
    }
    _cache = List.unmodifiable(next);
    return Success(_cache!);
  }

  @override
  Future<void> recordUse(QuickPhrase phrase) async {
    final index = phrase.presetIndex;
    if (index == null) return;
    try {
      final result = await _source.usePreset(index);
      if (result case Success(:final value)) {
        await _sequence.save(value.logId);
      }
    } on Object {
      // Logging is best effort and must not affect playback.
    }
  }
}
