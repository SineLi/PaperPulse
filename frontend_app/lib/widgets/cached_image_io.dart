import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/service/image_cache_service.dart';
import '../pages/setting_page.dart';

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
  String? _localPath;
  bool _networkFailed = false;
  bool _blockedByWifi = false;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(CachedArticleImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.articleId != widget.articleId ||
        oldWidget.imageUrl != widget.imageUrl) {
      _localPath = null;
      _networkFailed = false;
      _blockedByWifi = false;
      _resolveImage();
    }
  }

  Future<void> _resolveImage() async {
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
      onCached: (path) {
        if (mounted) setState(() => _localPath = path);
      },
    );
    if (cached != null && mounted) {
      setState(() => _localPath = cached);
    }
  }

  void _retry() {
    setState(() {
      _localPath = null;
      _networkFailed = false;
      _blockedByWifi = false;
    });
    _resolveImage();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
          if (mounted && !_networkFailed) {
            setState(() => _networkFailed = true);
          }
        });
        return _buildPlaceholder(colorScheme, tappable: true);
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _buildLoading(colorScheme, progress);
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
              '浠?Wi-Fi',
              style: TextStyle(fontSize: 11, color: colorScheme.outlineVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(ColorScheme colorScheme, ImageChunkEvent progress) {
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
            value: progress.expectedTotalBytes != null
                ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                : null,
          ),
        ),
      ),
    );
  }
}
