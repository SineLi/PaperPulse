import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/articledb.dart';
import '../models/article.dart';

/// 负责下载文章图片并缓存到本地文件系统，
/// 同时将缓存路径写回数据库。
class ImageCacheService {
  final ArticleDatabaseIO _articleDb;

  static const int _maxConcurrentDownloads = 3;
  static const Duration _retryBatchDelay = Duration(milliseconds: 500);

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      '(KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 Edg/144.0.0.0';

  /// 正在下载的 URL -> 等待通知的回调列表（避免重复请求，同时保留所有回调）
  final Map<String, List<void Function(String path)>> _downloading = {};

  /// 记录下载失败的文章 (articleId -> url)，以便在适当时候重试
  final Map<int, String> _failedArticles = {};

  int _activeDownloads = 0;
  final List<Completer<void>> _downloadWaiters = [];

  /// 仅在 Wi-Fi 下下载图片（由 SettingsController 同步更新）
  bool wifiOnly = false;

  late final Future<Directory> _cacheDirFuture = _initCacheDir();

  ImageCacheService({required ArticleDatabaseIO articleDb})
    : _articleDb = articleDb;

  Future<Directory> _initCacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(appDir.path, 'image_cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  String? getCachedPath({
    required int articleId,
    required String url,
    String? existingCachePath,
    void Function(String path)? onCached,
    bool? wifiOnly,
  }) {
    if (existingCachePath != null && existingCachePath.isNotEmpty) {
      if (File(existingCachePath).existsSync()) {
        return existingCachePath;
      }
    }

    _downloadAndCache(
      articleId,
      url,
      onCached,
      wifiOnly: wifiOnly ?? this.wifiOnly,
    );
    return null;
  }

  Future<void> _downloadAndCache(
    int articleId,
    String url,
    void Function(String path)? onCached, {
    bool wifiOnly = false,
  }) async {
    if (wifiOnly) {
      final result = await Connectivity().checkConnectivity();
      final isWifi = result.contains(ConnectivityResult.wifi);
      if (!isWifi) return;
    }

    if (_downloading.containsKey(url)) {
      if (onCached != null) {
        _downloading[url]!.add(onCached);
      }
      return;
    }
    _downloading[url] = onCached != null ? [onCached] : [];

    var slotAcquired = false;
    try {
      final cacheDir = await _cacheDirFuture;
      final ext = _extensionFromUrl(url);
      final fileName = '$articleId$ext';
      final file = File(p.join(cacheDir.path, fileName));

      if (await file.exists()) {
        await _articleDb.updateCachePath(articleId, file.path);
        _notifyCallbacks(url, file.path);
        return;
      }

      await _acquireDownloadSlot();
      slotAcquired = true;

      final headers = _buildHeaders(url);

      const maxRetries = 3;
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          final response = await http
              .get(Uri.parse(url), headers: headers)
              .timeout(const Duration(seconds: 30));

          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            await file.writeAsBytes(response.bodyBytes);
            await _articleDb.updateCachePath(articleId, file.path);
            _failedArticles.remove(articleId);
            _notifyCallbacks(url, file.path);
            return;
          }

          if (response.statusCode >= 400 &&
              response.statusCode < 500 &&
              response.statusCode != 403 &&
              response.statusCode != 429) {
            log(
              'Image download failed with ${response.statusCode}: $url',
              name: 'ImageCacheService',
            );
            _failedArticles[articleId] = url;
            return;
          }

          log(
            'Image download got ${response.statusCode} (attempt $attempt): $url',
            name: 'ImageCacheService',
          );
        } on SocketException catch (e) {
          log(
            'Network error while downloading image (attempt $attempt): $e',
            name: 'ImageCacheService',
          );
        } on HttpException catch (e) {
          log(
            'HTTP error while downloading image (attempt $attempt): $e',
            name: 'ImageCacheService',
          );
        } on http.ClientException catch (e) {
          log(
            'HTTP client error while downloading image (attempt $attempt): $e',
            name: 'ImageCacheService',
          );
        } catch (e) {
          log(
            'Unexpected error downloading image (attempt $attempt): $e',
            name: 'ImageCacheService',
          );
        }

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }
      log(
        'Image download failed after $maxRetries retries: $url',
        name: 'ImageCacheService',
      );
      _failedArticles[articleId] = url;
    } finally {
      if (slotAcquired) {
        _releaseDownloadSlot();
      }
      _downloading.remove(url);
    }
  }

  Future<void> _acquireDownloadSlot() async {
    if (_activeDownloads < _maxConcurrentDownloads) {
      _activeDownloads += 1;
      return;
    }

    final waiter = Completer<void>();
    _downloadWaiters.add(waiter);
    await waiter.future;
    _activeDownloads += 1;
  }

  void _releaseDownloadSlot() {
    if (_activeDownloads > 0) {
      _activeDownloads -= 1;
    }
    if (_downloadWaiters.isNotEmpty) {
      final next = _downloadWaiters.removeAt(0);
      if (!next.isCompleted) {
        next.complete();
      }
    }
  }

  void _notifyCallbacks(String url, String path) {
    final callbacks = _downloading[url];
    if (callbacks != null) {
      for (final cb in callbacks) {
        cb(path);
      }
    }
  }

  static Map<String, String> _buildHeaders(String url) {
    final uri = Uri.tryParse(url);
    final origin = uri != null ? '${uri.scheme}://${uri.host}' : '';
    return {
      'User-Agent': _userAgent,
      'Referer': origin.isNotEmpty ? '$origin/' : '',
      'Accept':
          'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Sec-Fetch-Dest': 'image',
      'Sec-Fetch-Mode': 'no-cors',
      'Sec-Fetch-Site': 'same-origin',
    };
  }

  Future<void> retryFailedImages() async {
    if (_failedArticles.isEmpty) return;

    final toRetry = Map<int, String>.from(_failedArticles);
    _failedArticles.clear();

    final tasks = <Future<void>>[];
    for (final entry in toRetry.entries) {
      tasks.add(_downloadAndCache(entry.key, entry.value, null));
    }
    final batches = _chunk(tasks, _maxConcurrentDownloads);
    for (var i = 0; i < batches.length; i++) {
      final batch = batches[i];
      await Future.wait(batch);
      if (i < batches.length - 1) {
        await Future.delayed(_retryBatchDelay);
      }
    }
  }

  Future<void> retryUncachedFromDb() async {
    final uncached = await _articleDb.getUncachedImageArticles(limit: 100);
    if (uncached.isEmpty) return;

    final items = uncached
        .map(
          (row) => (
            articleId: row[Article.colId] as int,
            url: row[Article.colGAUrl] as String?,
            cachePath: row[Article.colGACachePath] as String?,
          ),
        )
        .toList();
    await precacheArticles(items);
  }

  Future<void> precacheArticles(
    List<({int articleId, String? url, String? cachePath})> items, {
    bool? wifiOnly,
  }) async {
    if (wifiOnly ?? this.wifiOnly) {
      final result = await Connectivity().checkConnectivity();
      final isWifi = result.contains(ConnectivityResult.wifi);
      if (!isWifi) return;
    }
    final tasks = <Future<void>>[];
    for (final item in items) {
      if (item.url == null || item.url!.isEmpty) continue;
      if (item.cachePath != null &&
          item.cachePath!.isNotEmpty &&
          File(item.cachePath!).existsSync()) {
        continue;
      }
      tasks.add(_downloadAndCache(item.articleId, item.url!, null));
    }
    final batches = _chunk(tasks, _maxConcurrentDownloads);
    for (var i = 0; i < batches.length; i++) {
      final batch = batches[i];
      await Future.wait(batch);
      if (i < batches.length - 1) {
        await Future.delayed(_retryBatchDelay);
      }
    }
  }

  static String _extensionFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathExt = p.extension(uri.path).toLowerCase();
      if (['.jpg', '.jpeg', '.png', '.webp', '.gif'].contains(pathExt)) {
        return pathExt;
      }
    } catch (_) {}
    return '.jpg';
  }

  static List<List<T>> _chunk<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      chunks.add(
        list.sublist(i, i + size > list.length ? list.length : i + size),
      );
    }
    return chunks;
  }
}
