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
      throw _mapAuthException(e, fallbackMessage: '登录失败，请稍后重试');
    } on AuthActionException {
      rethrow;
    } catch (e) {
      throw AuthActionException(
        _toUserFriendlyMessage(e.toString(), fallbackMessage: '登录失败，请稍后重试'),
      );
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
      throw _mapAuthException(e, fallbackMessage: '验证码发送失败，请稍后重试');
    } on AuthActionException {
      rethrow;
    } catch (e) {
      throw AuthActionException(
        _toUserFriendlyMessage(e.toString(), fallbackMessage: '验证码发送失败，请稍后重试'),
      );
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
      throw _mapAuthException(e, fallbackMessage: '注册失败，请稍后重试');
    } on AuthActionException {
      rethrow;
    } catch (e) {
      throw AuthActionException(
        _toUserFriendlyMessage(e.toString(), fallbackMessage: '注册失败，请稍后重试'),
      );
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
      return AuthActionException(
        _toUserFriendlyMessage(detail, fallbackMessage: fallbackMessage),
      );
    }

    if (detail is Map<String, dynamic>) {
      final msg = detail['msg'];
      final retryAfterSeconds = _parseRetryAfter(detail['retry_after']);
      if (msg is String && msg.isNotEmpty) {
        final message = _toUserFriendlyMessage(
          msg,
          fallbackMessage: fallbackMessage,
          retryAfterSeconds: retryAfterSeconds,
        );
        return AuthActionException(
          message,
          retryAfterSeconds: retryAfterSeconds,
        );
      }
    }

    return AuthActionException(
      _toUserFriendlyMessage(error.message, fallbackMessage: fallbackMessage),
    );
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

  String _toUserFriendlyMessage(
    String rawMessage, {
    required String fallbackMessage,
    int? retryAfterSeconds,
  }) {
    final normalized = rawMessage.replaceAll('Exception: ', '').trim();
    final lower = normalized.toLowerCase();

    if (lower.contains('invalid credentials')) {
      return '用户名或密码错误';
    }
    if (lower.contains('username already exists')) {
      return '用户名已存在，请更换后重试';
    }
    if (lower.contains('email already registered')) {
      return '该邮箱已被注册，请直接登录或更换邮箱';
    }
    if (lower.contains('verification code expired or not found')) {
      return '验证码已过期或不存在，请重新获取';
    }
    if (lower.contains('invalid verification code')) {
      return '验证码错误，请重新输入';
    }
    if (lower.contains('too many failed attempts')) {
      return retryAfterSeconds == null
          ? '验证码错误次数过多，请稍后再试'
          : '验证码错误次数过多，请在 $retryAfterSeconds 秒后重试';
    }
    if (lower.contains('too many requests')) {
      return retryAfterSeconds == null
          ? '请求过于频繁，请稍后再试'
          : '请求过于频繁，请在 $retryAfterSeconds 秒后重试';
    }
    if (lower.contains('daily limit reached')) {
      return retryAfterSeconds == null
          ? '今日验证码发送次数已达上限，请稍后再试'
          : '今日验证码发送次数已达上限，请在 $retryAfterSeconds 秒后重试';
    }
    if (lower.contains('verification email delivery failed')) {
      return '验证码邮件发送失败，请稍后重试';
    }
    if (lower.contains('verification service unavailable')) {
      return '验证码服务暂不可用，请稍后重试';
    }
    if (lower.contains('authentication service unavailable')) {
      return '认证服务暂不可用，请稍后重试';
    }
    if (lower.contains('session expired or revoked') ||
        lower.contains('invalid or expired token') ||
        lower.contains('invalid refresh token')) {
      return '登录状态已失效，请重新登录';
    }
    if (lower.contains('invalid token payload')) {
      return '登录状态异常，请重新登录';
    }
    if (lower.contains('api base url is not configured')) {
      return '接口地址未配置，请在设置中检查服务器地址';
    }
    if (lower.contains('invalid api url')) {
      return '接口地址无效，请在设置中检查服务器地址';
    }
    if (lower.contains('timed out')) {
      return '请求超时，请检查网络后重试';
    }
    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable')) {
      return '网络连接失败，请检查网络或服务器地址';
    }
    if (lower.contains('access token not found in response') ||
        lower.contains('refresh token not found in response') ||
        lower.contains('invalid refresh response payload')) {
      return '服务器返回异常，请稍后重试';
    }

    return fallbackMessage;
  }

  Future<void> _storeTokens(Map<String, dynamic> response) async {
    final accessToken = response['access_token'];
    final refreshToken = response['refresh_token'];

    if (accessToken is! String || accessToken.isEmpty) {
      throw const AuthActionException('服务器返回异常，请稍后重试');
    }
    if (refreshToken is! String || refreshToken.isEmpty) {
      throw const AuthActionException('服务器返回异常，请稍后重试');
    }

    await _authStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }
}
