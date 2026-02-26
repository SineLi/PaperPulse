/// 阅读状态筛选
enum ReadStatusFilter {
  all,
  unread,
  read;

  String get label {
    switch (this) {
      case ReadStatusFilter.all:
        return '全部';
      case ReadStatusFilter.unread:
        return '未读';
      case ReadStatusFilter.read:
        return '已读';
    }
  }
}

/// 排序方式
enum SortOrder {
  /// 按文章推送顺序（article_id DESC，即后端入库顺序）
  byId,

  /// 按发表时间（published_date DESC）
  byDate;

  String get label {
    switch (this) {
      case SortOrder.byId:
        return '推送时间';
      case SortOrder.byDate:
        return '发表时间';
    }
  }

  String get description {
    switch (this) {
      case SortOrder.byId:
        return '最新推送优先';
      case SortOrder.byDate:
        return '最新发表优先';
    }
  }
}

/// 文章筛选条件（不可变值类型，重写 == / hashCode 以支持 ValueKey 比较）
class ArticleFilter {
  final ReadStatusFilter readStatus;
  final Set<int> journalIds;
  final Set<String> tags;
  final SortOrder sortOrder;

  const ArticleFilter({
    this.readStatus = ReadStatusFilter.all,
    this.journalIds = const {},
    this.tags = const {},
    this.sortOrder = SortOrder.byId,
  });

  /// 是否有任何非默认筛选条件处于激活状态
  bool get isActive =>
      readStatus != ReadStatusFilter.all ||
      journalIds.isNotEmpty ||
      tags.isNotEmpty ||
      sortOrder != SortOrder.byId;

  ArticleFilter copyWith({
    ReadStatusFilter? readStatus,
    Set<int>? journalIds,
    Set<String>? tags,
    SortOrder? sortOrder,
  }) {
    return ArticleFilter(
      readStatus: readStatus ?? this.readStatus,
      journalIds: journalIds ?? this.journalIds,
      tags: tags ?? this.tags,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ArticleFilter) return false;
    return readStatus == other.readStatus &&
        sortOrder == other.sortOrder &&
        _setEquals(journalIds, other.journalIds) &&
        _setEquals(tags, other.tags);
  }

  @override
  int get hashCode => Object.hash(
    readStatus,
    sortOrder,
    Object.hashAllUnordered(journalIds),
    Object.hashAllUnordered(tags),
  );

  static bool _setEquals<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  static const empty = ArticleFilter();
}
