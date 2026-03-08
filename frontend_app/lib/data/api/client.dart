import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_storage.dart';

class ApiException implements Exception {
  final String message;
  final int statusCode;

  const ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException: $message (Status code: $statusCode)';
}

class _TokenRefreshResult {
  final bool didRefresh;
  final ApiException? error;

  const _TokenRefreshResult({this.didRefresh = false, this.error});
}

class ApiClient {
  static const Duration _requestTimeout = Duration(seconds: 10);

  String baseUrl;

  final AuthStorage _authStorage;
  Future<_TokenRefreshResult>? _refreshInFlight;

  ApiClient({required String baseUrl, required AuthStorage? authStorage})
    : baseUrl = _normalizeBaseUrl(baseUrl),
      _authStorage = authStorage ?? AuthStorage();

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }

  Uri _buildUri(String endpoint) {
    if (baseUrl.isEmpty) {
      throw ApiException('API base URL is not configured.', 0);
    }

    final normalizedEndpoint = endpoint.startsWith('/')
        ? endpoint
        : '/$endpoint';
    final uriString = '$baseUrl$normalizedEndpoint';
    try {
      return Uri.parse(uriString);
    } on FormatException catch (e) {
      throw ApiException('Invalid API URL "$uriString": ${e.message}', 0);
    }
  }

  Future<Map<String, String>> _buildHeaders({
    bool includeAuthorization = true,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (!includeAuthorization) {
      return headers;
    }

    final token = await _authStorage.getToken();
    if (token == null || token.isEmpty) {
      return headers;
    }

    headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  bool _shouldRetryOnUnauthorized(String endpoint) {
    final normalizedEndpoint = endpoint.startsWith('/')
        ? endpoint
        : '/$endpoint';

    switch (normalizedEndpoint) {
      case '/auth/login':
      case '/auth/register':
      case '/auth/send_verification_code':
      case '/auth/refresh':
        return false;
      default:
        return true;
    }
  }

  Future<http.Response> _send(
    String endpoint,
    Future<http.Response> Function(Map<String, String> headers) request, {
    required bool retryOnUnauthorized,
  }) async {
    final response = await request(await _buildHeaders());
    if (!retryOnUnauthorized || response.statusCode != 401) {
      return response;
    }

    final refreshResult = await _refreshAccessToken();
    if (refreshResult.didRefresh) {
      return request(await _buildHeaders());
    }
    if (refreshResult.error != null) {
      throw refreshResult.error!;
    }

    return response;
  }

  Future<_TokenRefreshResult> _refreshAccessToken() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _performTokenRefresh();
    _refreshInFlight = future;
    future.whenComplete(() {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    });
    return future;
  }

  Future<_TokenRefreshResult> _performTokenRefresh() async {
    final refreshToken = await _authStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _authStorage.deleteToken();
      return const _TokenRefreshResult();
    }

    try {
      final response = await http
          .post(
            _buildUri('/auth/refresh'),
            headers: await _buildHeaders(includeAuthorization: false),
            body: jsonEncode({'refresh_token': refreshToken}),
          )
          .timeout(
            _requestTimeout,
            onTimeout: () {
              throw ApiException('Request to /auth/refresh timed out', 504);
            },
          );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic decoded = response.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          return const _TokenRefreshResult(
            error: ApiException('Invalid refresh response payload', 500),
          );
        }

        final accessToken = decoded['access_token'];
        final nextRefreshToken = decoded['refresh_token'];
        if (accessToken is! String ||
            accessToken.isEmpty ||
            nextRefreshToken is! String ||
            nextRefreshToken.isEmpty) {
          return const _TokenRefreshResult(
            error: ApiException('Invalid refresh response payload', 500),
          );
        }

        await _authStorage.saveTokens(
          accessToken: accessToken,
          refreshToken: nextRefreshToken,
        );
        return const _TokenRefreshResult(didRefresh: true);
      }

      if (response.statusCode >= 400 && response.statusCode < 500) {
        await _authStorage.deleteToken();
        return const _TokenRefreshResult();
      }

      return _TokenRefreshResult(
        error: ApiException(
          'Failed to refresh token: ${response.statusCode}: ${response.body}',
          response.statusCode,
        ),
      );
    } on ApiException catch (e) {
      return _TokenRefreshResult(error: e);
    } on FormatException catch (e) {
      return _TokenRefreshResult(
        error: ApiException('Invalid refresh response: ${e.message}', 500),
      );
    } catch (e) {
      return _TokenRefreshResult(
        error: ApiException('Failed to refresh token: $e', 0),
      );
    }
  }

  Future<Map<String, dynamic>> getJson(String endpoint) async {
    final response = await _send(
      endpoint,
      (headers) => http
          .get(_buildUri(endpoint), headers: headers)
          .timeout(
            _requestTimeout,
            onTimeout: () {
              throw ApiException('Request to $endpoint timed out', 504);
            },
          ),
      retryOnUnauthorized: _shouldRetryOnUnauthorized(endpoint),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body);
    }

    throw ApiException(
      'Failed to load data: ${response.statusCode}: ${response.body}',
      response.statusCode,
    );
  }

  Future<Map<String, dynamic>> postJson(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    final response = await _send(
      endpoint,
      (headers) => http
          .post(_buildUri(endpoint), headers: headers, body: jsonEncode(data))
          .timeout(
            _requestTimeout,
            onTimeout: () {
              throw ApiException('Request to $endpoint timed out', 504);
            },
          ),
      retryOnUnauthorized: _shouldRetryOnUnauthorized(endpoint),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body);
    }

    throw ApiException(
      'Failed to post data: ${response.statusCode}: ${response.body}',
      response.statusCode,
    );
  }

  Future<void> delete(String endpoint) async {
    final response = await _send(
      endpoint,
      (headers) => http
          .delete(_buildUri(endpoint), headers: headers)
          .timeout(
            _requestTimeout,
            onTimeout: () {
              throw ApiException('Request to $endpoint timed out', 504);
            },
          ),
      retryOnUnauthorized: _shouldRetryOnUnauthorized(endpoint),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    throw ApiException(
      'Failed to delete data: ${response.statusCode}: ${response.body}',
      response.statusCode,
    );
  }
}
