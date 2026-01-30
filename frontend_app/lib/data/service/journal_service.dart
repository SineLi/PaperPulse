import '../api/client.dart';
import '../models/journal.dart';

class JournalService {
  final ApiClient _apiClient;

  JournalService({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<Journal>> fetchJournals({int limit = 100, int offset = 0}) async {
    try {
      final response = await _apiClient.getJson(
        '/journals/?limit=$limit&offset=$offset',
      );
      final items = (response)['items'] as List<dynamic>;
      print(items);
      final journals = items
          .map((journalJson) => Journal.fromJson(journalJson))
          .toList();
      return journals;
    } catch (e) {
      throw Exception('Failed to fetch journals: $e');
    }
  }
}
