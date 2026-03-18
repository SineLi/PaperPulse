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
          .map((articleJson) => _parseArticle(articleJson))
          .toList();
      return articles;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw Exception('Failed to fetch articles: $e');
    }
  }

  Article _parseArticle(dynamic articleJson) {
    final article = Article.fromJson(articleJson as Map<String, dynamic>);
    return article.copyWith(
      graphicalAbstractFallbackUrl: _apiClient.resolveUrl(
        article.graphicalAbstractFallbackUrl,
      ),
    );
  }
}
