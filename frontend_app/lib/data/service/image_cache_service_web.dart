import '../db/articledb.dart';

class ImageCacheService {
  bool wifiOnly = false;

  ImageCacheService({required ArticleDatabaseIO articleDb});

  String? getCachedPath({
    required int articleId,
    required String url,
    String? existingCachePath,
    void Function(String path)? onCached,
    bool? wifiOnly,
  }) {
    return null;
  }

  Future<void> retryFailedImages() async {}

  Future<void> retryUncachedFromDb() async {}

  Future<void> precacheArticles(
    List<({int articleId, String? url, String? cachePath})> items, {
    bool? wifiOnly,
  }) async {}
}
