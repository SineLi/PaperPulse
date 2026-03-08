import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import 'auth_storage.dart';
import '../models/user.dart';
import '../service/user_services.dart';

class AuthActionException implements Exception {
  final String message;
  final int? retryAfterSeconds;

  const AuthActionException(this.message, {this.retryAfterSeconds});

  @override
  String toString() => message;
}

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
      await _storeTokens(response);
      _isLoggedIn = true;
      notifyListeners();
    } on ApiException catch (e) {
      throw _mapAuthException(e, fallbackMessage: 'Login failed');
    } catch (e) {
      throw AuthActionException('Login failed: $e');
    }
  }

  Future<void> logout() async {
    try {
      await _apiClient.postJson('/auth/logout', {});
    } catch (_) {
      // Ignore remote logout failures and clear local session regardless.
    }
    await _authStorage.deleteToken();
    _isLoggedIn = false;
    notifyListeners();
  }

  /// 检查本地是否存有 token（不验证有效性）
  Future<bool> hasToken() async {
    final accessToken = await _authStorage.getToken();
    if (accessToken != null && accessToken.isNotEmpty) {
      return true;
    }

    final refreshToken = await _authStorage.getRefreshToken();
    return refreshToken != null && refreshToken.isNotEmpty;
  }

  Future<void> sendVerificationCode({required String email}) async {
    try {
      await _apiClient.postJson('/auth/send_verification_code', {
        "email": email,
      });
    } on ApiException catch (e) {
      throw _mapAuthException(
        e,
        fallbackMessage: 'Failed to send verification code',
      );
    } catch (e) {
      throw AuthActionException('Failed to send verification code: $e');
    }
  }

  Future<void> register(
    String username,
    String email,
    String password,
    String verificationCode,
  ) async {
    final Map<String, dynamic> registerRequest = {
      "username": username,
      "email": email,
      "password": password,
      "verification_code": verificationCode,
    };
    try {
      final response = await _apiClient.postJson(
        '/auth/register',
        registerRequest,
      );
      await _storeTokens(response);
    } on ApiException catch (e) {
      throw _mapAuthException(e, fallbackMessage: 'Registration failed');
    } catch (e) {
      throw AuthActionException('Registration failed: $e');
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
      final hasLocalToken = await hasToken();
      if (!hasLocalToken && _isLoggedIn) {
        _isLoggedIn = false;
        notifyListeners();
      }
      // 其他意外错误（DNS、超时等），不删 token
      return null;
    }
  }

  AuthActionException _mapAuthException(
    ApiException error, {
    required String fallbackMessage,
  }) {
    final detail = _extractErrorDetail(error.message);

    if (detail is String && detail.isNotEmpty) {
      return AuthActionException(detail);
    }

    if (detail is Map<String, dynamic>) {
      final msg = detail['msg'];
      final retryAfterSeconds = _parseRetryAfter(detail['retry_after']);
      if (msg is String && msg.isNotEmpty) {
        final message = retryAfterSeconds == null
            ? msg
            : '$msg. Retry after ${retryAfterSeconds}s.';
        return AuthActionException(
          message,
          retryAfterSeconds: retryAfterSeconds,
        );
      }
    }

    return AuthActionException('$fallbackMessage: ${error.message}');
  }

  dynamic _extractErrorDetail(String message) {
    final jsonStart = message.indexOf('{');
    if (jsonStart < 0) {
      return null;
    }

    try {
      final payload = jsonDecode(message.substring(jsonStart));
      if (payload is Map<String, dynamic>) {
        return payload['detail'];
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  int? _parseRetryAfter(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  Future<void> _storeTokens(Map<String, dynamic> response) async {
    final accessToken = response['access_token'];
    final refreshToken = response['refresh_token'];

    if (accessToken is! String || accessToken.isEmpty) {
      throw AuthActionException('Access token not found in response');
    }
    if (refreshToken is! String || refreshToken.isEmpty) {
      throw AuthActionException('Refresh token not found in response');
    }

    await _authStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }
}
