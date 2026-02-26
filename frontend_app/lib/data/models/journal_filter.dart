/// SCI 收录状态筛选
enum SciFilter {
  all,
  sci1,
  sci2,
  sci3,
  sci4,
  nonSci;

  String get label {
    switch (this) {
      case SciFilter.all:
        return '全部';
      case SciFilter.sci1:
        return '1区';
      case SciFilter.sci2:
        return '2区';
      case SciFilter.sci3:
        return '3区';
      case SciFilter.sci4:
        return '4区';
      case SciFilter.nonSci:
        return '非 SCI';
    }
  }
}

/// 期刊筛选条件（不可变值类型，重写 == / hashCode）
class JournalFilter {
  /// 出版商集合（空 = 全部）
  final Set<String> publishers;

  /// SCI 收录状态
  final SciFilter sciFilter;

  /// CAS 分区集合，对应 CASUp 字段（空 = 全部）
  final Set<String> casCategories;

  /// 影响因子最低值（0.0 = 不限）；取值范围 0–20，步长 4
  final double ifMin;

  const JournalFilter({
    this.publishers = const {},
    this.sciFilter = SciFilter.all,
    this.casCategories = const {},
    this.ifMin = 0.0,
  });

  bool get isActive =>
      publishers.isNotEmpty ||
      sciFilter != SciFilter.all ||
      casCategories.isNotEmpty ||
      ifMin != 0.0;

  JournalFilter copyWith({
    Set<String>? publishers,
    SciFilter? sciFilter,
    Set<String>? casCategories,
    double? ifMin,
  }) {
    return JournalFilter(
      publishers: publishers ?? this.publishers,
      sciFilter: sciFilter ?? this.sciFilter,
      casCategories: casCategories ?? this.casCategories,
      ifMin: ifMin ?? this.ifMin,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! JournalFilter) return false;
    return sciFilter == other.sciFilter &&
        ifMin == other.ifMin &&
        _setEquals(publishers, other.publishers) &&
        _setEquals(casCategories, other.casCategories);
  }

  @override
  int get hashCode => Object.hash(
    sciFilter,
    ifMin,
    Object.hashAllUnordered(publishers),
    Object.hashAllUnordered(casCategories),
  );

  static bool _setEquals<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  static const empty = JournalFilter();
}
