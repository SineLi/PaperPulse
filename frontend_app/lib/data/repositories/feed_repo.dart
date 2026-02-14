import '../service/feed_service.dart';
import '../service/image_cache_service.dart';
import '../db/articledb.dart';
import '../models/article.dart';
import 'journal_repo.dart';

class FeedRepo {
  final FeedService _feedService;
  final ArticleDatabaseIO _articleDatabaseIO;
  final JournalRepo? _journalRepo;
  final ImageCacheService? _imageCacheService;

  // 内存缓存 Publisher
  final Map<int, String> _publisherCache = {};

  FeedRepo({
    required FeedService feedService,
    required ArticleDatabaseIO articleDatabaseIO,
    JournalRepo? journalRepo,
    ImageCacheService? imageCacheService,
  }) : _feedService = feedService,
       _articleDatabaseIO = articleDatabaseIO,
       _journalRepo = journalRepo,
       _imageCacheService = imageCacheService;

  Future<List<Article>> getLocalArticles({
    int limit = 50,
    int offset = 0,
  }) async {
    List<Article> articles = await _articleDatabaseIO.getArticles(
      limit,
      offset,
    );

    if (_journalRepo == null) return articles;

    // 填充 Publisher 信息
    List<Article> enrichedArticles = [];
    for (var article in articles) {
      String publisher = await _getPublisher(article.journalId);
      enrichedArticles.add(article.copyWith(publisher: publisher));
    }

    return enrichedArticles;
  }

  Future<String> _getPublisher(int journalId) async {
    if (_publisherCache.containsKey(journalId)) {
      return _publisherCache[journalId]!;
    }

    if (_journalRepo != null) {
      final journal = await _journalRepo.getLocalJournalById(journalId);
      if (journal != null) {
        _publisherCache[journalId] = journal.publisher ?? '';
        return journal.publisher ?? '';
      }
    }

    return '';
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

      // 后台预缓存新文章的图片
      if (_imageCacheService != null) {
        _imageCacheService.precacheArticles(
          newArticles
              .map(
                (a) => (
                  articleId: a.articleId,
                  url: a.graphicalAbstractUrl,
                  cachePath: a.graphicalAbstractCachePath,
                ),
              )
              .toList(),
        );
      }
    }
    // 刷新时重试之前下载失败的图片 + 数据库中未缓存的图片
    if (_imageCacheService != null) {
      _imageCacheService.retryFailedImages();
      _imageCacheService.retryUncachedFromDb();
    }

    return newArticlesCount;
  }
}
