import 'package:marieum_app/core/error/failure.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class PrefsKeys {
  static const installationInitialized = 'installation_initialized';
  static const ttsRate = 'tts_rate';
  static const ttsVolume = 'tts_volume';
  static const largeText = 'large_text';
  static const speakMode = 'speak_mode';
  static const loginUserId = 'login_user_id';
  static const lastLogId = 'last_log_id';
}

abstract interface class PrefsBackend {
  String? readString(String key);
  bool? readBool(String key);
  Future<void> writeString(String key, String value);
  Future<void> writeBool(String key, {required bool value});
  Future<void> remove(String key);
}

class SharedPrefsBackend implements PrefsBackend {
  SharedPrefsBackend(this._preferences);
  final SharedPreferences _preferences;
  @override
  String? readString(String key) => _preferences.getString(key);
  @override
  bool? readBool(String key) => _preferences.getBool(key);
  @override
  Future<void> writeString(String key, String value) async {
    if (!await _preferences.setString(key, value)) {
      throw StateError('Write failed.');
    }
  }

  @override
  Future<void> writeBool(String key, {required bool value}) async {
    if (!await _preferences.setBool(key, value)) {
      throw StateError('Write failed.');
    }
  }

  @override
  Future<void> remove(String key) async {
    if (!await _preferences.remove(key)) throw StateError('Removal failed.');
  }
}

class PrefsStore {
  PrefsStore(this._backend);
  final PrefsBackend _backend;
  T _read<T>(T Function() operation) {
    try {
      return operation();
    } on Object catch (error) {
      throw StorageFailure(cause: error);
    }
  }

  Future<void> _write(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object catch (error) {
      throw StorageFailure(cause: error);
    }
  }

  String? readString(String key) => _read(() => _backend.readString(key));
  bool? readBool(String key) => _read(() => _backend.readBool(key));
  Future<void> writeString(String key, String value) =>
      _write(() => _backend.writeString(key, value));
  Future<void> writeBool(String key, {required bool value}) =>
      _write(() => _backend.writeBool(key, value: value));
  Future<void> remove(String key) => _write(() => _backend.remove(key));
}
