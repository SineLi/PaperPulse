import '../api/client.dart';

class UserServices {
  final ApiClient _apiClient;

  UserServices({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<int>> fetchSubscribedJournalIds() async {
    try {
      final response = await _apiClient.getJson('/users/me/journals');
      final items = (response)['items'] as List<dynamic>;
      final journalIds = items.map((item) => item as int).toList();
      return journalIds;
    } catch (e) {
      throw Exception('Failed to fetch subscribed journal IDs: $e');
    }
  }

  Future<void> followJournal(int journalId) async {
    try {
      await _apiClient.postJson('/journals/$journalId/follow', {});
    } on ApiException catch (apierr) {
      if (apierr.statusCode == 409) {
        // Already following, ignore
        return;
      }
      if (apierr.statusCode == 404) {
        throw Exception('Journal with ID $journalId not found');
      }
      throw Exception('API Error ${apierr.statusCode}: ${apierr.message}');
    } catch (e) {
      throw Exception('Failed to follow journal $journalId: $e');
    }
  }

  Future<void> unfollowJournal(int journalId) async {
    try {
      await _apiClient.delete('/journals/$journalId/follow');
    } on ApiException catch (apierr) {
      if (apierr.statusCode == 404) {
        throw Exception('Journal with ID $journalId not found');
      }
      throw Exception('API Error ${apierr.statusCode}: ${apierr.message}');
    } catch (e) {
      throw Exception('Failed to unfollow journal $journalId: $e');
    }
  }
}
