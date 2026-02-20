import 'dart:convert';
import '../auth/auth_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException: $message (Status code: $statusCode)';
}

class ApiClient {
  String _baseUrl;
  String get baseUrl => _baseUrl;
  set baseUrl(String value) => _baseUrl = _normalizeBaseUrl(value);

  final AuthStorage _authStorage;
  ApiClient({required String baseUrl, required AuthStorage? authStorage})
    : _baseUrl = _normalizeBaseUrl(baseUrl),
      _authStorage = authStorage ?? AuthStorage();

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }

  Uri _buildUri(String endpoint) {
    if (_baseUrl.isEmpty) {
      throw ApiException(
        'API 基础地址未配置。请在 设置 > 网络 中设置。',
        0,
      );
    }

    final normalizedEndpoint = endpoint.startsWith('/')
        ? endpoint
        : '/$endpoint';
    return Uri.parse('$_baseUrl$normalizedEndpoint');
  }

  Future<Map<String, String>> _buildHeaders() async {
    final token = await _authStorage.getToken();
    if (token == null) {
      return {'Content-Type': 'application/json'};
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> getJson(String endpoint) async {
    final headers = await _buildHeaders();
    final response = await http
        .get(_buildUri(endpoint), headers: headers)
        .timeout(
          Duration(seconds: 10),
          onTimeout: () {
            throw ApiException('Request to $endpoint timed out', 504);
          },
        );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      throw ApiException(
        'Failed to load data: ${response.statusCode}: ${response.body}',
        response.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> postJson(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    final headers = await _buildHeaders();
    final response = await http
        .post(_buildUri(endpoint), headers: headers, body: jsonEncode(data))
        .timeout(
          Duration(seconds: 10),
          onTimeout: () {
            throw ApiException('Request to $endpoint timed out', 504);
          },
        );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body);
    } else {
      throw ApiException(
        'Failed to post data: ${response.statusCode}: ${response.body}',
        response.statusCode,
      );
    }
  }

  Future<void> delete(String endpoint) async {
    final headers = await _buildHeaders();
    final response = await http
        .delete(_buildUri(endpoint), headers: headers)
        .timeout(
          Duration(seconds: 10),
          onTimeout: () {
            throw ApiException('Request to $endpoint timed out', 504);
          },
        );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    } else {
      throw ApiException(
        'Failed to delete data: ${response.statusCode}: ${response.body}',
        response.statusCode,
      );
    }
  }
}
