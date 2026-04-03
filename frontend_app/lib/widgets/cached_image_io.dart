import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/service/image_cache_service.dart';
import '../settings/settings_controller.dart';

class CachedArticleImage extends StatefulWidget {
  final int articleId;
  final String imageUrl;
  final String? cachePath;
  final BoxFit fit;
  final double? width;
  final double? height;

  const CachedArticleImage({
    super.key,
    required this.articleId,
    required this.imageUrl,
    this.cachePath,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  State<CachedArticleImage> createState() => _CachedArticleImageState();
}

class _CachedArticleImageState extends State<CachedArticleImage> {
  static const int _maxFallbackRetries = 3;
  static const Duration _fallbackRetryDelay = Duration(seconds: 2);

  String? _localPath;
  bool _networkFailed = false;
  bool _blockedByWifi = false;
  bool _fallbackAttempted = false;
  bool _fallbackLoading = false;
  bool _showFallbackNetwork = false;
  bool _sourceCacheQueued = false;
  int _fallbackRetryCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeImage();
  }

  @override
  void didUpdateWidget(CachedArticleImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.articleId != widget.articleId ||
        oldWidget.imageUrl != widget.imageUrl) {
      _localPath = null;
      _networkFailed = false;
      _blockedByWifi = false;
      _fallbackAttempted = false;
      _fallbackLoading = false;
      _showFallbackNetwork = false;
      _sourceCacheQueued = false;
      _fallbackRetryCount = 0;
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

    if (wifiOnly) {
      final result = await Connectivity().checkConnectivity();
      final isWifi = result.contains(ConnectivityResult.wifi);
      if (!isWifi) {
        if (mounted) setState(() => _blockedByWifi = true);
        return;
      }
    }

    final cached = cacheService.getCachedPath(
      articleId: widget.articleId,
      url: widget.imageUrl,
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
            _fallbackRetryCount = 0;
          });
        }
      },
    );
    if (cached != null && mounted) {
      setState(() {
        _localPath = cached;
        _fallbackLoading = false;
        _fallbackRetryCount = 0;
      });
    }
  }

  String? _effectiveFallbackUrl(ImageCacheService cacheService) {
    return cacheService.buildFallbackUrl(widget.articleId);
  }

  void _queueSourceCache() {
    if (_sourceCacheQueued || _localPath != null || widget.imageUrl.isEmpty) {
      return;
    }

    _sourceCacheQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _localPath != null) {
        return;
      }
      _resolveImage();
    });
  }

  void _retry() {
    setState(() {
      _localPath = null;
      _networkFailed = false;
      _blockedByWifi = false;
      _fallbackAttempted = false;
      _fallbackLoading = false;
      _showFallbackNetwork = false;
      _sourceCacheQueued = false;
      _fallbackRetryCount = 0;
    });
    _initializeImage();
  }

  void _scheduleFallbackRetry(String fallbackUrl) {
    if (_fallbackRetryCount >= _maxFallbackRetries) {
      setState(() {
        _showFallbackNetwork = false;
        _fallbackLoading = false;
        _networkFailed = true;
      });
      return;
    }

    _fallbackRetryCount += 1;
    setState(() {
      _showFallbackNetwork = false;
      _fallbackLoading = true;
      _networkFailed = false;
    });

    Future.delayed(_fallbackRetryDelay, () {
      if (!mounted || _localPath != null) {
        return;
      }

      setState(() {
        _showFallbackNetwork = true;
        _fallbackLoading = true;
        _networkFailed = false;
      });
      _resolveImage(preferFallback: true).whenComplete(() {
        if (mounted && _localPath == null && !_showFallbackNetwork) {
          setState(() => _fallbackLoading = false);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cacheService = context.read<ImageCacheService>();
    final fallbackUrl = _effectiveFallbackUrl(cacheService);

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

    if (_blockedByWifi) {
      return _buildWifiPlaceholder(colorScheme);
    }

    if (_showFallbackNetwork && fallbackUrl != null && fallbackUrl.isNotEmpty) {
      return Image.network(
        fallbackUrl,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (context, error, stackTrace) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            _scheduleFallbackRetry(fallbackUrl);
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _networkFailed) {
            return;
          }

          if (!_fallbackAttempted &&
              fallbackUrl != null &&
              fallbackUrl.isNotEmpty) {
            setState(() {
              _fallbackAttempted = true;
              _fallbackLoading = true;
              _showFallbackNetwork = true;
              _fallbackRetryCount = 0;
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
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          _queueSourceCache();
        }
        return child;
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
      onTap: _retry,
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
              '仅Wi-Fi',
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
          child: CircularProgressIndicator(strokeWidth: 2, value: value),
        ),
      ),
    );
  }
}
