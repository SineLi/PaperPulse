import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

/// 将瀑布流拆成可懒加载的小块，由标准 [SliverList] 负责滚动。
///
/// `SliverMasonryGrid` 被全宽组件切成多个 sliver 后，在跨段回收子组件时
/// 可能产生错误的滚动偏移修正。这里让每个瀑布块只负责自身布局，滚动范围
/// 统一交给稳定的线性 sliver 管理，同时允许指定条目前插入双列通栏内容。
class ChunkedMasonrySliver extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Map<int, Widget> fullWidthLeading;
  final int chunkSize;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final EdgeInsetsGeometry padding;

  const ChunkedMasonrySliver({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.fullWidthLeading = const {},
    this.chunkSize = 20,
    this.mainAxisSpacing = 8,
    this.crossAxisSpacing = 8,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
  }) : assert(chunkSize > 0);

  @override
  Widget build(BuildContext context) {
    final chunkCount = (itemCount / chunkSize).ceil();
    return SliverPadding(
      padding: padding,
      sliver: SliverList.builder(
        itemCount: chunkCount,
        itemBuilder: (context, chunkIndex) {
          final start = chunkIndex * chunkSize;
          final end = (start + chunkSize).clamp(0, itemCount);
          final tiles = <Widget>[];

          for (var index = start; index < end; index++) {
            final leading = fullWidthLeading[index];
            if (leading != null) {
              tiles.add(
                StaggeredGridTile.fit(
                  crossAxisCellCount: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: leading,
                  ),
                ),
              );
            }
            tiles.add(
              StaggeredGridTile.fit(
                crossAxisCellCount: 1,
                child: KeyedSubtree(
                  key: ValueKey('masonry-item-$index'),
                  child: itemBuilder(context, index),
                ),
              ),
            );
          }

          return Padding(
            key: ValueKey('masonry-chunk-$chunkIndex'),
            padding: EdgeInsets.only(
              bottom: chunkIndex == chunkCount - 1 ? 0 : mainAxisSpacing,
            ),
            child: StaggeredGrid.count(
              crossAxisCount: 2,
              mainAxisSpacing: mainAxisSpacing,
              crossAxisSpacing: crossAxisSpacing,
              children: tiles,
            ),
          );
        },
      ),
    );
  }
}
