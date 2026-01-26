import 'dart:convert';
import '../auth/auth_storage.dart';
import 'package:http/http.dart' as http;

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

  Future<dynamic> getJson(String endpoint) async {
    final headers = await _buildHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
        'Failed to load data: ${response.statusCode}: ${response.body}',
      );
    }
  }

  Future<dynamic> postJson(String endpoint, Map<String, dynamic> data) async {
    final headers = await _buildHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(data),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
        'Failed to post data: ${response.statusCode}: ${response.body}',
      );
    }
  }
}
