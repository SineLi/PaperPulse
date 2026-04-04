import 'package:shared_preferences/shared_preferences.dart';

class AuthStorage {
  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessToken, token);
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_kAccessToken, accessToken),
      prefs.setString(_kRefreshToken, refreshToken),
    ]);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAccessToken);
  }

  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kRefreshToken);
  }

  Future<void> deleteToken() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_kAccessToken),
      prefs.remove(_kRefreshToken),
    ]);
  }
}
