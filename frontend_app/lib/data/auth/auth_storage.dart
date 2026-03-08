import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthStorage {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';

  Future<void> saveToken(String token) async {
    await _storage.write(key: _kAccessToken, value: token);
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _kAccessToken, value: accessToken),
      _storage.write(key: _kRefreshToken, value: refreshToken),
    ]);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _kAccessToken);
  }

  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _kRefreshToken);
  }

  Future<void> deleteToken() async {
    await Future.wait([
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
    ]);
  }
}
