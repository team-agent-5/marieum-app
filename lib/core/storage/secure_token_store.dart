import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/core/storage/token_vault.dart';

class SecureTokenStore {
  SecureTokenStore({required this._vault, required this._prefs});
  final TokenVault _vault;
  final PrefsStore _prefs;
  Future<void>? _initialization;
  Future<void> _tail = Future.value();

  Future<void> initialize() => _initialization ??=
      Future<void>.sync(() async {
        if (_prefs.readBool(PrefsKeys.installationInitialized) != true) {
          await _vault.clearAll();
          await _prefs.writeBool(
            PrefsKeys.installationInitialized,
            value: true,
          );
        }
      }).catchError((Object error) {
        _initialization = null;
        throw error is StorageFailure ? error : StorageFailure(cause: error);
      });

  Future<T> _run<T>(Future<T> Function() operation) {
    final result = _tail.then((_) async {
      await initialize();
      try {
        return await operation();
      } on Object catch (error) {
        throw StorageFailure(cause: error);
      }
    });
    // A failed operation must not poison subsequent reads or logout cleanup.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<String?> read() => _run(_vault.read);
  Future<void> write(String token) => _run(() => _vault.write(token));
  Future<void> clear() => _run(_vault.delete);
}
