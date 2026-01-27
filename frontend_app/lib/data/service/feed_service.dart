import '../api/client.dart';
import '../models/article.dart';

class FeedService {
  final ApiClient _apiClient;

  FeedService({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<Article>> fetchArticles({int limit = 100, int offset = 0}) async {
    try {
      final response = await _apiClient.getJson(
        '/articles/feed?limit=$limit&offset=$offset',
      );
      final items = (response)['items'] as List<dynamic>;
      final articles = items
          .map((articleJson) => Article.fromJson(articleJson))
          .toList();
      return articles;
    } catch (e) {
      throw Exception('Failed to fetch articles: $e');
    }
  }
}
