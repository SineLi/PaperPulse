import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/service/image_cache_service.dart';
import '../pages/setting_page.dart';

/// 优先从本地缓存加载图片，未缓存时显示网络图片并触发后台缓存。
class CachedArticleImage extends StatefulWidget {
  final int articleId;
  final String imageUrl;
  final String? fallbackImageUrl;
  final String? cachePath;
  final BoxFit fit;
  final double? width;
  final double? height;

  const CachedArticleImage({
    super.key,
    required this.articleId,
    required this.imageUrl,
    this.fallbackImageUrl,
    this.cachePath,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  State<CachedArticleImage> createState() => _CachedArticleImageState();
}

class _CachedArticleImageState extends State<CachedArticleImage> {
  String? _localPath;
  bool _networkFailed = false;
  bool _blockedByWifi = false;
  bool _fallbackAttempted = false;
  bool _fallbackLoading = false;
  bool _showFallbackNetwork = false;

  @override
  void initState() {
    super.initState();
    _initializeImage();
  }

  @override
  void didUpdateWidget(CachedArticleImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.articleId != widget.articleId ||
        oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.fallbackImageUrl != widget.fallbackImageUrl) {
      _localPath = null;
      _networkFailed = false;
      _blockedByWifi = false;
      _fallbackAttempted = false;
      _fallbackLoading = false;
      _showFallbackNetwork = false;
      _initializeImage();
    }
  }

  Future<void> _initializeImage() async {
    final settingsController = context.read<SettingsController>();
    final cacheService = context.read<ImageCacheService>();
    final wifiOnly = settingsController.setting.wifiOnlyImages;

    if (wifiOnly) {
      final result = await Connectivity().checkConnectivity();
      final isWifi = result.contains(ConnectivityResult.wifi);
      if (!isWifi) {
        if (mounted) {
          setState(() => _blockedByWifi = true);
        }
        return;
      }
    }

    final cached = await cacheService.getExistingCachedPath(
      articleId: widget.articleId,
      existingCachePath: widget.cachePath,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _blockedByWifi = false;
      _localPath = cached;
    });
  }

  Future<void> _resolveImage({bool preferFallback = false}) async {
    final settingsController = context.read<SettingsController>();
    final cacheService = context.read<ImageCacheService>();
    final wifiOnly = settingsController.setting.wifiOnlyImages;

    // Wi-Fi 专属：非 WiFi 时不加载。
    if (wifiOnly) {
      final result = await Connectivity().checkConnectivity();
      final isWifi = result.contains(ConnectivityResult.wifi);
      if (!isWifi) {
        if (mounted) setState(() => _blockedByWifi = true);
        return;
      }
    }

    // 先检查本地缓存路径；未命中时由服务在后台触发下载。
    final cached = cacheService.getCachedPath(
      articleId: widget.articleId,
      url: widget.imageUrl,
      fallbackUrl: widget.fallbackImageUrl,
      existingCachePath: widget.cachePath,
      wifiOnly: wifiOnly,
      preferFallback: preferFallback,
      onCached: (path) {
        if (mounted) {
          setState(() {
            _localPath = path;
            _fallbackLoading = false;
            _showFallbackNetwork = false;
            _networkFailed = false;
          });
        }
      },
    );
    if (cached != null && mounted) {
      setState(() {
        _localPath = cached;
        _fallbackLoading = false;
      });
    }
  }

  void _retry() {
    setState(() {
      _localPath = null;
      _networkFailed = false;
      _blockedByWifi = false;
      _fallbackAttempted = false;
      _fallbackLoading = false;
      _showFallbackNetwork = false;
    });
    _initializeImage();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 优先展示本地文件。
    if (_localPath != null) {
      return Image.file(
        File(_localPath!),
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (context, error, stackTrace) =>
            _buildPlaceholder(colorScheme, tappable: true),
      );
    }

    // 仅 Wi-Fi 模式下，非 WiFi 时展示提示占位符。
    if (_blockedByWifi) {
      return _buildWifiPlaceholder(colorScheme);
    }

    if (_showFallbackNetwork &&
        widget.fallbackImageUrl != null &&
        widget.fallbackImageUrl!.isNotEmpty) {
      return Image.network(
        widget.fallbackImageUrl!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (context, error, stackTrace) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _showFallbackNetwork = false;
              _fallbackLoading = false;
              _networkFailed = true;
            });
          });
          return _buildPlaceholder(colorScheme, tappable: true);
        },
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            return child;
          }
          return _buildLoading(
            colorScheme,
            value: progress.expectedTotalBytes != null
                ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                : null,
          );
        },
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          return _buildLoading(colorScheme);
        },
      );
    }

    if (_fallbackLoading) {
      return _buildLoading(colorScheme);
    }

    if (_networkFailed) {
      return _buildPlaceholder(colorScheme, tappable: true);
    }

    return Image.network(
      widget.imageUrl,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      errorBuilder: (context, error, stackTrace) {
        // 网络加载失败后，标记错误状态以支持点击重试。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _networkFailed) {
            return;
          }

          if (!_fallbackAttempted &&
              widget.fallbackImageUrl != null &&
              widget.fallbackImageUrl!.isNotEmpty) {
            setState(() {
              _fallbackAttempted = true;
              _fallbackLoading = true;
              _showFallbackNetwork = true;
            });
            _resolveImage(preferFallback: true).whenComplete(() {
              if (mounted && _localPath == null) {
                setState(() => _fallbackLoading = false);
              }
            });
          } else {
            setState(() => _networkFailed = true);
          }
        });
        return _buildPlaceholder(colorScheme, tappable: true);
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _buildLoading(
          colorScheme,
          value: progress.expectedTotalBytes != null
              ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
              : null,
        );
      },
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme, {bool tappable = false}) {
    final placeholder = Container(
      width: widget.width,
      height: widget.height,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        tappable ? Icons.refresh_rounded : Icons.image_outlined,
        color: colorScheme.outlineVariant,
        size: 28,
      ),
    );

    if (tappable) {
      return GestureDetector(onTap: _retry, child: placeholder);
    }
    return placeholder;
  }

  Widget _buildWifiPlaceholder(ColorScheme colorScheme) {
    return GestureDetector(
      onTap: _retry, // 点击后重新检测网络并重试。
      child: Container(
        width: widget.width,
        height: widget.height,
        color: colorScheme.surfaceContainerHighest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              color: colorScheme.outlineVariant,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              '仅 Wi-Fi',
              style: TextStyle(fontSize: 11, color: colorScheme.outlineVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(ColorScheme colorScheme, {double? value}) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: value,
          ),
        ),
      ),
    );
  }
}
