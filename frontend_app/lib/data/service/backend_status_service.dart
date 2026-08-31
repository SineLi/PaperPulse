import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BackendStatus {
  final String version;

  const BackendStatus({required this.version});
}

class BackendStatusException implements Exception {
  final String message;

  const BackendStatusException(this.message);

  @override
  String toString() => message;
}

class BackendStatusService {
  static const Duration _requestTimeout = Duration(seconds: 8);

  final http.Client _client;

  BackendStatusService({http.Client? client})
    : _client = client ?? http.Client();

  Future<BackendStatus> fetch(String baseUrl) async {
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final baseUri = Uri.tryParse(normalized);
    if (baseUri == null ||
        !(baseUri.isScheme('http') || baseUri.isScheme('https')) ||
        baseUri.host.isEmpty) {
      throw const BackendStatusException('请输入有效的 http/https 地址');
    }

    final response = await _client
        .get(Uri.parse('$normalized/status'))
        .timeout(
          _requestTimeout,
          onTimeout: () => throw const BackendStatusException('连接后端超时'),
        );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendStatusException('状态接口返回 HTTP ${response.statusCode}');
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['status'] != 'ok' ||
          decoded['service'] != 'paperpulse-backend' ||
          decoded['version'] is! String ||
          (decoded['version'] as String).trim().isEmpty) {
        throw const BackendStatusException('未识别为有效的 PaperPulse 后端');
      }
      return BackendStatus(version: (decoded['version'] as String).trim());
    } on FormatException {
      throw const BackendStatusException('后端状态响应格式无效');
    }
  }
}

class BackendStatusController extends ChangeNotifier {
  final BackendStatusService _service;
  final String clientVersion;

  BackendStatusController(this._service, {required this.clientVersion});

  BackendStatus? _status;
  bool _isChecking = false;

  BackendStatus? get status => _status;
  bool get isChecking => _isChecking;
  bool get hasUpdate =>
      _status != null && compareVersions(_status!.version, clientVersion) > 0;
  bool get hasVersionMismatch =>
      _status != null && compareVersions(_status!.version, clientVersion) != 0;

  Future<BackendStatus> check(String baseUrl) async {
    _isChecking = true;
    notifyListeners();
    try {
      final result = await _service.fetch(baseUrl);
      _status = result;
      return result;
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  Future<void> checkSilently(String baseUrl) async {
    try {
      await check(baseUrl);
    } catch (_) {
      // A configured backend may be temporarily offline during app startup.
    }
  }

  void clear() {
    if (_status == null) return;
    _status = null;
    notifyListeners();
  }

  static int compareVersions(String left, String right) {
    final leftParts = _numericVersionParts(left);
    final rightParts = _numericVersionParts(right);
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < length; index++) {
      final leftPart = index < leftParts.length ? leftParts[index] : 0;
      final rightPart = index < rightParts.length ? rightParts[index] : 0;
      if (leftPart != rightPart) return leftPart.compareTo(rightPart);
    }
    return 0;
  }

  static List<int> _numericVersionParts(String version) {
    final normalized = version.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final core = normalized.split(RegExp(r'[-+]')).first;
    return core.split('.').map((part) => int.tryParse(part) ?? 0).toList();
  }
}
