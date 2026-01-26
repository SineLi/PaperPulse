import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthStorage {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _kAccessToken = 'access_token';

  Future<void> saveToken(String token) async {
    await _storage.write(key: _kAccessToken, value: token);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _kAccessToken);
  }

  Future<void> deleteToken() async {
    await _storage.delete(key: _kAccessToken);
  }
}
