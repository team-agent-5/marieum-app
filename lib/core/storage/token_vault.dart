import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class TokenVault {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
  Future<void> clearAll();
}

class PlatformTokenVault implements TokenVault {
  PlatformTokenVault({FlutterSecureStorage? plugin})
    : _plugin = plugin ?? const FlutterSecureStorage();
  static const tokenKey = 'access_token';
  final FlutterSecureStorage _plugin;
  @override
  Future<String?> read() => _plugin.read(key: tokenKey);
  @override
  Future<void> write(String token) =>
      _plugin.write(key: tokenKey, value: token);
  @override
  Future<void> delete() => _plugin.delete(key: tokenKey);
  @override
  Future<void> clearAll() => _plugin.deleteAll();
}
