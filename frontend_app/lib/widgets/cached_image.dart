import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/service/image_cache_service.dart';

/// 优先从本地缓存加载图片，未缓存时显示网络图片并触发后台缓存。
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
      _resolveImage();
    }
  }

  void _resolveImage() {
    final cacheService = context.read<ImageCacheService>();
    final cached = cacheService.getCachedPath(
      articleId: widget.articleId,
      url: widget.imageUrl,
      existingCachePath: widget.cachePath,
      onCached: (path) {
        if (mounted) setState(() => _localPath = path);
      },
    );
    if (cached != null) {
      _localPath = cached;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 优先本地文件
    if (_localPath != null) {
      return Image.file(
        File(_localPath!),
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (context, error, stackTrace) =>
            _buildPlaceholder(colorScheme),
      );
    }

    // 回退到网络图片
    return Image.network(
      widget.imageUrl,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      errorBuilder: (context, error, stackTrace) =>
          _buildPlaceholder(colorScheme),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _buildLoading(colorScheme, progress);
      },
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_outlined,
        color: colorScheme.outlineVariant,
        size: 28,
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
