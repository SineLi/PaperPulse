import '../service/feed_service.dart';
import '../db/articledb.dart';
import '../models/article.dart';

class FeedRepo {
  final FeedService _feedService;
  final ArticleDatabaseIO _articleDatabaseIO;

  FeedRepo({
    required FeedService feedService,
    required ArticleDatabaseIO articleDatabaseIO,
  }) : _feedService = feedService,
       _articleDatabaseIO = articleDatabaseIO;

  Future<List<Article>> getLocalArticles({
    int limit = 50,
    int offset = 0,
  }) async {
    return await _articleDatabaseIO.getArticles(limit, offset);
  }

  Future<int> refreshArticles() async {
    final maxId = await _articleDatabaseIO.getMaxArticleId();
    int newArticlesCount = 0;

    for (var offset = 0; ; offset += 100) {
      final articles = await _feedService.fetchArticles(
        limit: 100,
        offset: offset,
      );

      if (articles.isEmpty) {
        break;
      }
      if (articles.every((article) => article.articleId <= maxId)) {
        break;
      }
      final newArticles = articles
          .where((article) => article.articleId > maxId)
          .toList();

      await _articleDatabaseIO.addArticles(newArticles);
      newArticlesCount += newArticles.length;
    }
    return newArticlesCount;
  }
}
