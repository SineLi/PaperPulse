import '../api/client.dart';
import 'auth_storage.dart';

class AuthServices {
  final ApiClient _apiClient;
  final AuthStorage _authStorage;

  AuthServices({required ApiClient apiClient, required AuthStorage authStorage})
    : _authStorage = authStorage,
      _apiClient = apiClient;

  Future<void> login(String username, String password) async {
    final Map<String, dynamic> loginRequest = {
      "username": username,
      "password": password,
    };
    try {
      final response = await _apiClient.postJson('/auth/login', loginRequest);
      final token = response['access_token'];
      if (token != null) {
        await _authStorage.saveToken(token);
      } else {
        throw Exception('Token not found in response');
      }
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  Future<void> logout() async {
    await _authStorage.deleteToken();
  }
}
