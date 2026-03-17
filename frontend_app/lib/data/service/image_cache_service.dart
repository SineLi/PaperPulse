import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../db/articledb.dart';
import '../models/article.dart';

/// 负责下载文章图片并缓存到本地文件系统，
/// 同时将缓存路径写回数据库。
class ImageCacheService {
  final ArticleDatabaseIO _articleDb;

  static const int _maxConcurrentDownloads = 3;
  static const Duration _retryBatchDelay = Duration(milliseconds: 500);
  static const Duration _backendMinInterval = Duration(milliseconds: 500);

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      '(KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 Edg/144.0.0.0';

  final Map<int, List<void Function(String path)>> _downloading = {};
  final Map<int, ({String url, String? fallbackUrl})> _failedArticles = {};

  int _activeDownloads = 0;
  final List<Completer<void>> _downloadWaiters = [];
  Future<void> _backendRateGate = Future<void>.value();
  DateTime _nextBackendRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

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

  /// 获取文章图片的本地缓存路径。
  /// 如果已缓存则直接返回路径；否则后台下载并返回 null。
  /// [onCached] 下载完成后的回调（可用于刷新 UI）。
  /// [wifiOnly] 为 true 时仅在 Wi-Fi 下触发下载。
  String? getCachedPath({
    required int articleId,
    required String url,
    String? fallbackUrl,
    String? existingCachePath,
    void Function(String path)? onCached,
    bool? wifiOnly,
    bool preferFallback = false,
  }) {
    // 已有缓存路径且文件存在
    if (existingCachePath != null && existingCachePath.isNotEmpty) {
      if (File(existingCachePath).existsSync()) {
        return existingCachePath;
      }
    }

    _downloadAndCache(
      articleId,
      url,
      onCached,
      fallbackUrl: fallbackUrl,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      preferFallback: preferFallback,
    );
    return null;
  }

  Future<void> _downloadAndCache(
    int articleId,
    String url,
    void Function(String path)? onCached, {
    String? fallbackUrl,
    bool wifiOnly = false,
    bool preferFallback = false,
  }) async {
    // Wi-Fi 专属模式：非 Wi-Fi 网络时跳过下载
    if (wifiOnly) {
      final result = await Connectivity().checkConnectivity();
      final isWifi = result.contains(ConnectivityResult.wifi);
      if (!isWifi) return;
    }
    // 已在下载中 → 注册回调后返回，由先前的下载任务负责通知
    if (_downloading.containsKey(articleId)) {
      if (onCached != null) {
        _downloading[articleId]!.add(onCached);
      }
      return;
    }
    _downloading[articleId] = onCached != null ? [onCached] : [];

    var slotAcquired = false;
    try {
      final cacheDir = await _cacheDirFuture;
      final file = File(p.join(cacheDir.path, '$articleId.img'));

      if (await file.exists()) {
        // 文件存在但 DB 记录缺失，补写 DB
        await _articleDb.updateCachePath(articleId, file.path);
        _notifyCallbacks(articleId, file.path);
        return;
      }

      await _acquireDownloadSlot();
      slotAcquired = true;

      final candidates = <({String url, bool rateLimited})>[
        if (preferFallback &&
            fallbackUrl != null &&
            fallbackUrl.isNotEmpty)
          (url: fallbackUrl, rateLimited: true),
        if (!preferFallback) (url: url, rateLimited: false),
        if (!preferFallback &&
            fallbackUrl != null &&
            fallbackUrl.isNotEmpty)
          (url: fallbackUrl, rateLimited: true),
      ];

      for (final candidate in candidates) {
        final body = await _downloadBytes(
          candidate.url,
          rateLimited: candidate.rateLimited,
        );
        if (body == null) {
          continue;
        }

        await file.writeAsBytes(body);
        await _articleDb.updateCachePath(articleId, file.path);
        _failedArticles.remove(articleId);
        _notifyCallbacks(articleId, file.path);
        return;
      }

      _failedArticles[articleId] = (url: url, fallbackUrl: fallbackUrl);
    } finally {
      if (slotAcquired) {
        _releaseDownloadSlot();
      }
      _downloading.remove(articleId);
    }
  }

  Future<List<int>?> _downloadBytes(
    String url, {
    required bool rateLimited,
  }) async {
    final headers = _buildHeaders(url);
    const maxRetries = 3;

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (rateLimited) {
          await _waitForBackendRateLimit();
        }

        final response = await http
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return response.bodyBytes;
        }

        if (response.statusCode >= 400 &&
            response.statusCode < 500 &&
            response.statusCode != 403 &&
            response.statusCode != 429) {
          log(
            'Image download failed with ${response.statusCode}: $url',
            name: 'ImageCacheService',
          );
          return null;
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

    return null;
  }

  Future<void> _waitForBackendRateLimit() {
    final completer = Completer<void>();
    final previous = _backendRateGate;
    _backendRateGate = completer.future;

    return previous.then((_) async {
      final now = DateTime.now();
      final wait = _nextBackendRequestAt.difference(now);
      if (wait > Duration.zero) {
        await Future.delayed(wait);
      }
      _nextBackendRequestAt = DateTime.now().add(_backendMinInterval);
      completer.complete();
    });
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

  void _notifyCallbacks(int articleId, String path) {
    final callbacks = _downloading[articleId];
    if (callbacks != null) {
      for (final cb in callbacks) {
        cb(path);
      }
    }
  }

  /// 根据 URL 的域名构造浏览器级别的请求头（Referer + UA），
  /// 解决出版商防盗链导致的 403 问题。
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

  /// 重试之前下载失败的图片（供刷新时调用）
  Future<void> retryFailedImages() async {
    if (_failedArticles.isEmpty) return;

    final toRetry = Map<int, ({String url, String? fallbackUrl})>.from(
      _failedArticles,
    );
    _failedArticles.clear();

    final tasks = <Future<void>>[];
    for (final entry in toRetry.entries) {
      tasks.add(
        _downloadAndCache(
          entry.key,
          entry.value.url,
          null,
          fallbackUrl: entry.value.fallbackUrl,
        ),
      );
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

  /// 扫描数据库中未缓存的图片并尝试下载
  Future<void> retryUncachedFromDb() async {
    final uncached = await _articleDb.getUncachedImageArticles(limit: 100);
    if (uncached.isEmpty) return;

    final items = uncached
        .map(
          (row) => (
            articleId: row[Article.colId] as int,
            url: row[Article.colGAUrl] as String?,
            cachePath: row[Article.colGACachePath] as String?,
            fallbackUrl: row[Article.colGAFallbackUrl] as String?,
          ),
        )
        .toList();
    await precacheArticles(items);
  }

  /// 批量预缓存多篇文章的图片
  Future<void> precacheArticles(
    List<({int articleId, String? url, String? cachePath, String? fallbackUrl})>
        items, {
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
      tasks.add(
        _downloadAndCache(
          item.articleId,
          item.url!,
          null,
          fallbackUrl: item.fallbackUrl,
        ),
      );
    }
    // 并发但限制为 _maxConcurrentDownloads 个，并在批次间做短暂等待
    final batches = _chunk(tasks, _maxConcurrentDownloads);
    for (var i = 0; i < batches.length; i++) {
      final batch = batches[i];
      await Future.wait(batch);
      if (i < batches.length - 1) {
        await Future.delayed(_retryBatchDelay);
      }
    }
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
