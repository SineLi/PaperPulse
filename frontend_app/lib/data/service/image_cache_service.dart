import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../db/articledb.dart';

/// 负责下载文章图片并缓存到本地文件系统，
/// 同时将缓存路径写回数据库。
class ImageCacheService {
  final ArticleDatabaseIO _articleDb;

  /// 内存中记录正在下载的 URL，避免重复请求
  final Set<String> _downloading = {};

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
  String? getCachedPath({
    required int articleId,
    required String url,
    String? existingCachePath,
    void Function(String path)? onCached,
  }) {
    // 已有缓存路径且文件存在
    if (existingCachePath != null && existingCachePath.isNotEmpty) {
      if (File(existingCachePath).existsSync()) {
        return existingCachePath;
      }
    }

    // 触发后台下载
    _downloadAndCache(articleId, url, onCached);
    return null;
  }

  Future<void> _downloadAndCache(
    int articleId,
    String url,
    void Function(String path)? onCached,
  ) async {
    if (_downloading.contains(url)) return;
    _downloading.add(url);

    try {
      final cacheDir = await _cacheDirFuture;
      final ext = _extensionFromUrl(url);
      final fileName = '${articleId}$ext';
      final file = File(p.join(cacheDir.path, fileName));

      if (await file.exists()) {
        // 文件存在但 DB 记录缺失，补写 DB
        await _articleDb.updateCachePath(articleId, file.path);
        onCached?.call(file.path);
        return;
      }

      const maxRetries = 3;
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          final response = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 30));

          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            await file.writeAsBytes(response.bodyBytes);
            await _articleDb.updateCachePath(articleId, file.path);
            onCached?.call(file.path);
            return;
          }

          // 4xx 客户端错误不重试
          if (response.statusCode >= 400 && response.statusCode < 500) return;
        } on SocketException catch (_) {
          // 网络不可达
        } on HttpException catch (_) {
          // HTTP 协议错误
        } on http.ClientException catch (_) {
          // http 包客户端异常
        } catch (_) {
          // TimeoutException 等其他异常
        }

        if (attempt < maxRetries) {
          // 指数退避：1s, 2s
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    } finally {
      _downloading.remove(url);
    }
  }

  /// 批量预缓存多篇文章的图片
  Future<void> precacheArticles(
    List<({int articleId, String? url, String? cachePath})> items,
  ) async {
    final tasks = <Future<void>>[];
    for (final item in items) {
      if (item.url == null || item.url!.isEmpty) continue;
      if (item.cachePath != null &&
          item.cachePath!.isNotEmpty &&
          File(item.cachePath!).existsSync())
        continue;
      tasks.add(_downloadAndCache(item.articleId, item.url!, null));
    }
    // 并发但限制为 4 个
    final batches = _chunk(tasks, 4);
    for (final batch in batches) {
      await Future.wait(batch);
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
