enum FeedCardStyle { compact, featuredImage, masonry }

extension FeedCardStyleMetadata on FeedCardStyle {
  String get displayName => switch (this) {
    FeedCardStyle.compact => '经典摘要',
    FeedCardStyle.featuredImage => '大图封面',
    FeedCardStyle.masonry => '瀑布流',
  };

  String get description => switch (this) {
    FeedCardStyle.compact => '紧凑排列标题、期刊信息与缩略图',
    FeedCardStyle.featuredImage => '顶部期刊栏搭配醒目的横向大图',
    FeedCardStyle.masonry => '双列流式布局，适合快速浏览图形摘要',
  };

  String get previewAsset => switch (this) {
    FeedCardStyle.compact => 'assets/card_style_previews/compact.svg',
    FeedCardStyle.featuredImage =>
      'assets/card_style_previews/featured_image.svg',
    FeedCardStyle.masonry => 'assets/card_style_previews/masonry.svg',
  };

  static FeedCardStyle fromStorage(String? value) {
    return FeedCardStyle.values.firstWhere(
      (style) => style.name == value,
      orElse: () => FeedCardStyle.masonry,
    );
  }
}
