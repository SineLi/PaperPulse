import '../api/client.dart';
import '../models/journal.dart';

class JournalCatalogStatus {
  final String revision;
  final int count;

  const JournalCatalogStatus({required this.revision, required this.count});
}

class JournalService {
  final ApiClient _apiClient;

  JournalService({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<JournalCatalogStatus> fetchCatalogStatus() async {
    try {
      final response = await _apiClient.getJson('/journals/status');
      final revision = response['revision'];
      final count = response['count'];
      if (revision is! String ||
          revision.isEmpty ||
          count is! int ||
          count < 0) {
        throw const FormatException('Invalid journal catalog status');
      }
      return JournalCatalogStatus(revision: revision, count: count);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw Exception('Failed to fetch journal catalog status: $e');
    }
  }

  Future<List<Journal>> fetchJournals({int limit = 100, int offset = 0}) async {
    try {
      final response = await _apiClient.getJson(
        '/journals/?limit=$limit&offset=$offset',
      );
      final items = (response)['items'] as List<dynamic>;
      final journals = items
          .map((journalJson) => Journal.fromJson(journalJson))
          .toList();
      return journals;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw Exception('Failed to fetch journals: $e');
    }
  }
}
