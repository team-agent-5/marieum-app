import 'package:marieum_app/core/storage/prefs_store.dart';

class SequenceStore {
  SequenceStore(this._prefs);
  final PrefsStore _prefs;
  String? get lastLogId => _prefs.readString(PrefsKeys.lastLogId);
  Future<void> save(String logId) =>
      _prefs.writeString(PrefsKeys.lastLogId, logId);
  // Authentication owns clearing per-user sequence state on logout/account change.
  Future<void> clear() => _prefs.remove(PrefsKeys.lastLogId);
}
