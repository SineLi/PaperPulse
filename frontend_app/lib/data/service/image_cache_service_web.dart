import '../db/articledb.dart';

class ImageCacheService {
  bool wifiOnly = false;
  String baseUrl = '';

  ImageCacheService({required ArticleDatabaseIO articleDb});

  Future<String?> getExistingCachedPath({
    required int articleId,
    String? existingCachePath,
  }) async {
    return null;
  }

  String? getCachedPath({
    required int articleId,
    required String url,
    String? existingCachePath,
    void Function(String path)? onCached,
    bool? wifiOnly,
    bool preferFallback = false,
  }) {
    return null;
  }

  String? buildFallbackUrl(int articleId) {
    if (articleId <= 0) {
      return null;
    }

    final normalizedBaseUrl = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (normalizedBaseUrl.isEmpty) {
      return null;
    }

    const fallbackBucketSize = 10000;
    final bucketStart =
        ((articleId - 1) ~/ fallbackBucketSize) * fallbackBucketSize + 1;
    final bucketEnd = bucketStart + fallbackBucketSize - 1;
    final path =
        '/media/article-images/$bucketStart-$bucketEnd/$articleId.webp';
    return Uri.parse(normalizedBaseUrl).resolve(path).toString();
  }

  Future<void> retryFailedImages() async {}

  Future<void> retryUncachedFromDb() async {}

  Future<void> precacheArticles(
    List<({int articleId, String? url, String? cachePath})> items, {
    bool? wifiOnly,
  }) async {}
}
