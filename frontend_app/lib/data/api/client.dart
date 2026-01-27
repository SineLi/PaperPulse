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
  final String baseUrl;

  final AuthStorage _authStorage;
  ApiClient({required this.baseUrl, required AuthStorage? authStorage})
    : _authStorage = authStorage ?? AuthStorage();

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
        .get(Uri.parse('$baseUrl$endpoint'), headers: headers)
        .timeout(
          Duration(seconds: 10),
          onTimeout: () {
            throw Exception('Request to $endpoint timed out');
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
        .post(
          Uri.parse('$baseUrl$endpoint'),
          headers: headers,
          body: jsonEncode(data),
        )
        .timeout(
          Duration(seconds: 10),
          onTimeout: () {
            throw Exception('Request to $endpoint timed out');
          },
        );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      throw ApiException(
        'Failed to post data: ${response.statusCode}: ${response.body}',
        response.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> deleteJson(String endpoint) async {
    final headers = await _buildHeaders();
    final response = await http
        .delete(Uri.parse('$baseUrl$endpoint'), headers: headers)
        .timeout(
          Duration(seconds: 10),
          onTimeout: () {
            throw Exception('Request to $endpoint timed out');
          },
        );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      throw ApiException(
        'Failed to delete data: ${response.statusCode}: ${response.body}',
        response.statusCode,
      );
    }
  }
}
