import 'dart:io';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import 'auth_storage.dart';
import '../models/user.dart';
import '../service/user_services.dart';

class AuthServices extends ChangeNotifier {
  final ApiClient _apiClient;
  final AuthStorage _authStorage;
  final UserServices userServices;

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  AuthServices({
    required ApiClient apiClient,
    required AuthStorage authStorage,
    required this.userServices,
  }) : _authStorage = authStorage,
       _apiClient = apiClient {
    // 初始化检查状态
    checkLoginStatus();
  }

  Future<void> checkLoginStatus() async {
    final status = await hasToken();
    if (_isLoggedIn != status) {
      _isLoggedIn = status;
      notifyListeners();
    }
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final Map<String, dynamic> loginRequest = {
      "username": username,
      "password": password,
    };
    try {
      final response = await _apiClient.postJson('/auth/login', loginRequest);
      final token = response['access_token'];
      if (token != null) {
        await _authStorage.saveToken(token);
        _isLoggedIn = true;
        notifyListeners();
      } else {
        throw Exception('Token not found in response');
      }
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  Future<void> logout() async {
    await _authStorage.deleteToken();
    _isLoggedIn = false;
    notifyListeners();
  }

  /// 检查本地是否存有 token（不验证有效性）
  Future<bool> hasToken() async {
    final token = await _authStorage.getToken();
    return token != null && token.isNotEmpty;
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
    // 本地无 token 直接返回 null
    final hasLocalToken = await hasToken();
    if (!hasLocalToken) {
      if (_isLoggedIn) {
        _isLoggedIn = false;
        notifyListeners();
      }
      return null;
    } else {
      if (!_isLoggedIn) {
        _isLoggedIn = true;
        // Don't notify here if we are just verifying.
        // But if state was false, we should correct it.
        // notifyListeners(); // Wait, this might cause rebuild loop if called from build.
        // Better to just update internal state without notify if possible, or notify carefully.
      }
    }

    try {
      final user = await userServices.fetchCurrentUser();
      if (!_isLoggedIn) {
        _isLoggedIn = true;
        notifyListeners();
      }
      return user;
    } on ApiException catch (apierr) {
      if (apierr.statusCode == 401 || apierr.statusCode == 403) {
        await _authStorage.deleteToken();
        _isLoggedIn = false;
        notifyListeners();
        return null;
      }
      // 其他 API 错误（如 500）不删 token，rethrow 给调用方处理
      rethrow;
    } on SocketException {
      // 无网络连接，不删 token，返回 null 表示无法验证
      return null;
    } catch (_) {
      // 其他意外错误（DNS、超时等），不删 token
      return null;
    }
  }
}
