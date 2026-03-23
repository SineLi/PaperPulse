import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/service/image_cache_service.dart';

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
  bool _networkFailed = false;
  bool _fallbackAttempted = false;
  bool _showFallbackNetwork = false;
  bool _fallbackLoading = false;

  void _retry() {
    setState(() {
      _networkFailed = false;
      _fallbackAttempted = false;
      _showFallbackNetwork = false;
      _fallbackLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cacheService = context.read<ImageCacheService>();
    final fallbackUrl = cacheService.buildFallbackUrl(widget.articleId);

    if (_networkFailed) {
      return _buildPlaceholder(colorScheme, tappable: true);
    }

    if (_fallbackLoading) {
      return _buildLoading(
        colorScheme,
        ImageChunkEvent(cumulativeBytesLoaded: 0, expectedTotalBytes: null),
      );
    }

    if (_showFallbackNetwork && fallbackUrl != null && fallbackUrl.isNotEmpty) {
      return Image.network(
        fallbackUrl,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (context, error, stackTrace) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_networkFailed) {
              setState(() {
                _showFallbackNetwork = false;
                _fallbackLoading = false;
                _networkFailed = true;
              });
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

    return Image.network(
      widget.imageUrl,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      errorBuilder: (context, error, stackTrace) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_networkFailed) {
            if (!_fallbackAttempted &&
                fallbackUrl != null &&
                fallbackUrl.isNotEmpty) {
              setState(() {
                _fallbackAttempted = true;
                _fallbackLoading = true;
                _showFallbackNetwork = true;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _fallbackLoading) {
                  setState(() => _fallbackLoading = false);
                }
              });
            } else {
              setState(() => _networkFailed = true);
            }
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
