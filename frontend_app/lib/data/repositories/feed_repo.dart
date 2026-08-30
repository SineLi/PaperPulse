import '../service/feed_service.dart';
import '../service/image_cache_service.dart';
import '../db/articledb.dart';
import '../models/article.dart';
import '../models/article_filter.dart';
import 'journal_repo.dart';

class FeedRepo {
  final FeedService _feedService;
  final ArticleDatabaseIO _articleDatabaseIO;
  final JournalRepo? _journalRepo;
  final ImageCacheService? _imageCacheService;
  Future<int>? _refreshInFlight;

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
    ArticleFilter filter = ArticleFilter.empty,
  }) async {
    List<Article> articles = await _articleDatabaseIO.getArticles(
      limit,
      offset,
      filter,
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

  Future<List<Article>> getLocalFavoriteArticles({
    int limit = 50,
    int offset = 0,
    ArticleFilter filter = ArticleFilter.empty,
  }) async {
    List<Article> articles = await _articleDatabaseIO.getFavoriteArticles(
      limit: limit,
      offset: offset,
      filter: filter,
    );

    if (_journalRepo == null) return articles;

    List<Article> enrichedArticles = [];
    for (var article in articles) {
      String publisher = await _getPublisher(article.journalId);
      enrichedArticles.add(article.copyWith(publisher: publisher));
    }

    return enrichedArticles;
  }

  /// 搜索本地文章（按标题/摘要/期刊名模糊匹配）
  Future<List<Article>> searchLocalArticles(
    String query, {
    int limit = 50,
    int offset = 0,
  }) async {
    List<Article> articles = await _articleDatabaseIO.searchArticles(
      query,
      limit: limit,
      offset: offset,
    );

    if (_journalRepo == null) return articles;

    List<Article> enrichedArticles = [];
    for (var article in articles) {
      String publisher = await _getPublisher(article.journalId);
      enrichedArticles.add(article.copyWith(publisher: publisher));
    }

    return enrichedArticles;
  }

  /// 仅搜索本地已收藏文章。
  Future<List<Article>> searchLocalFavoriteArticles(
    String query, {
    int limit = 50,
    int offset = 0,
  }) async {
    final articles = await _articleDatabaseIO.searchFavoriteArticles(
      query,
      limit: limit,
      offset: offset,
    );

    if (_journalRepo == null) return articles;

    final enrichedArticles = <Article>[];
    for (final article in articles) {
      final publisher = await _getPublisher(article.journalId);
      enrichedArticles.add(article.copyWith(publisher: publisher));
    }
    return enrichedArticles;
  }

  /// 返回当前文章库中实际出现的期刊列表，供筛选面板使用。
  Future<List<({int id, String name, String abbr})>> getFilterableJournals() =>
      _articleDatabaseIO.getDistinctJournalsInArticles();

  /// 返回当前文章库中所有出现过的话题标签（maintag + subtags 合集）。
  Future<List<String>> getFilterableTags() =>
      _articleDatabaseIO.getDistinctTagsInArticles();

  Future<int> refreshArticles() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _performRefreshArticles();
    _refreshInFlight = future;
    future.whenComplete(() {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    });
    return future;
  }

  Future<int> _performRefreshArticles() async {
    // 使用独立的 feed 同步 ID，不受收藏单篇拉取的影响
    final lastSyncId = await _articleDatabaseIO.getLastFeedSyncId();
    int newArticlesCount = 0;
    int maxSeenId = lastSyncId;

    for (var offset = 0; ; offset += 100) {
      final articles = await _feedService.fetchArticles(
        limit: 100,
        offset: offset,
      );

      if (articles.isEmpty) {
        break;
      }
      if (articles.every((article) => article.articleId <= lastSyncId)) {
        break;
      }
      final newArticles = articles
          .where((article) => article.articleId > lastSyncId)
          .toList();

      await _articleDatabaseIO.addArticles(newArticles);
      newArticlesCount += newArticles.length;

      // 记录本次刷新看到的最大 ID
      for (var article in newArticles) {
        if (article.articleId > maxSeenId) {
          maxSeenId = article.articleId;
        }
      }

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

    // 更新 feed 同步 ID
    if (maxSeenId > lastSyncId) {
      await _articleDatabaseIO.setLastFeedSyncId(maxSeenId);
    }

    // 刷新时重试之前下载失败的图片 + 数据库中未缓存的图片
    if (_imageCacheService != null) {
      _imageCacheService.retryFailedImages();
      _imageCacheService.retryUncachedFromDb();
    }

    return newArticlesCount;
  }
}
