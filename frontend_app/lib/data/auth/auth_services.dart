import '../api/client.dart';
import 'auth_storage.dart';
import '../models/user.dart';
import '../service/user_services.dart';

class AuthServices {
  final ApiClient _apiClient;
  final AuthStorage _authStorage;
  final UserServices userServices;

  AuthServices({
    required ApiClient apiClient,
    required AuthStorage authStorage,
    required this.userServices,
  }) : _authStorage = authStorage,
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

  Future<void> register(String username, String email, String password) async {
    final Map<String, dynamic> registerRequest = {
      "username": username,
      "email": email,
      "password": password,
    };
    try {
      final response = await _apiClient.postJson(
        '/auth/register',
        registerRequest,
      );
      final token = response['access_token'];
      if (token != null) {
        await _authStorage.saveToken(token);
      } else {
        throw Exception('Token not found in response');
      }
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  Future<User?> tryGetCurrentUser() async {
    try {
      final user = await userServices.fetchCurrentUser();
      return user;
    } on ApiException catch (apierr) {
      if (apierr.statusCode == 401 || apierr.statusCode == 403) {
        await _authStorage.deleteToken();
        return null;
      }
      throw Exception('API Error ${apierr.statusCode}: ${apierr.message}');
    } catch (e) {
      throw Exception('Failed to fetch current user: $e');
    }
  }
}
