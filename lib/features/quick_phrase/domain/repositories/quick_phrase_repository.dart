import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/quick_phrase.dart';

abstract interface class QuickPhraseRepository {
  List<QuickPhrase> load();
  Future<Result<List<QuickPhrase>>> add(String text);
  Future<Result<List<QuickPhrase>>> remove(String id);

  /// Records use on the server when the phrase maps to a server preset.
  /// Never blocks playback; failures are swallowed.
  Future<void> recordUse(QuickPhrase phrase);
}
