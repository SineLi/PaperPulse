import 'package:frontend_app/data/models/journal.dart';

import 'database.dart';
import '../models/article.dart';
import '../models/article_filter.dart';
import 'package:sqflite/sqflite.dart';

class ArticleDatabaseIO {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  Future<int> addArticle(Article article) async {
    final db = await dbHelper.database;
    return await db.insert(
      Article.tableArticles,
      article.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<Article?> getArticle(int id) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      Article.tableArticles,
      where: '${Article.colId} = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Article.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<void> addArticles(List<Article> articles) async {
    final db = await dbHelper.database;
    final batch = db.batch();
    for (var article in articles) {
      batch.insert(
        Article.tableArticles,
        article.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Article>> getArticles(
    int limit,
    int offset,
    ArticleFilter filter,
  ) async {
    final db = await dbHelper.database;
    final q = _buildFilterQuery(filter);
    final maps = await db.query(
      Article.tableArticles,
      where: q.where.isEmpty ? null : q.where,
      whereArgs: q.whereArgs.isEmpty ? null : q.whereArgs,
      limit: limit,
      offset: offset,
      orderBy: q.orderBy,
    );
    return maps.map((map) => Article.fromMap(map)).toList();
  }

  Future<int> setFavorite(int id, bool isFavorite) async {
    final db = await dbHelper.database;
    return await db.update(
      Article.tableArticles,
      {Article.colIsFavorite: isFavorite ? 1 : 0},
      where: '${Article.colId} = ?',
      whereArgs: [id],
    );
  }

  Future<int> setRead(int id, bool isRead) async {
    final db = await dbHelper.database;
    return await db.update(
      Article.tableArticles,
      {Article.colIsRead: isRead ? 1 : 0},
      where: '${Article.colId} = ?',
      whereArgs: [id],
    );
  }

  Future<List<Article>> getFavoriteArticles({
    int limit = 500,
    int offset = 0,
    ArticleFilter filter = ArticleFilter.empty,
  }) async {
    final db = await dbHelper.database;
    // 先应用通用筛选，再额外附加 is_favorite = 1 的固定条件
    final q = _buildFilterQuery(
      filter,
      baseWhere: '${Article.colIsFavorite} = ?',
      baseArgs: [1],
    );
    final maps = await db.query(
      Article.tableArticles,
      where: q.where,
      whereArgs: q.whereArgs,
      orderBy: q.orderBy,
      limit: limit,
      offset: offset,
    );
    final articles = maps.map((map) => Article.fromMap(map)).toList();
    return articles;
  }

  Future<List<Article>> getUnreadArticles({
    int limit = 500,
    int offset = 0,
  }) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      Article.tableArticles,
      where: '${Article.colIsRead} = ?',
      whereArgs: [0],
      orderBy: '${Article.colId} DESC',
      limit: limit,
      offset: offset,
    );
    final articles = maps.map((map) => Article.fromMap(map)).toList();
    return articles;
  }

  Future<void> setFavoriteWithSync(int id, bool isFavorite) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      await txn.update(
        Article.tableArticles,
        {Article.colIsFavorite: isFavorite ? 1 : 0},
        where: '${Article.colId} = ?',
        whereArgs: [id],
      );
      await txn.insert("sync_queue", {
        'article_id': id,
        'action': isFavorite ? 'favorite' : 'unfavorite',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  Future<void> setReadWithSync(int id, bool isRead) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      await txn.update(
        Article.tableArticles,
        {Article.colIsRead: isRead ? 1 : 0},
        where: '${Article.colId} = ?',
        whereArgs: [id],
      );
      await txn.insert("sync_queue", {
        'article_id': id,
        'action': isRead ? 'read' : 'unread',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  /// 获取上次 feed 批量刷新的最大 article_id
  /// 与 getMaxArticleId 不同，此值只在 feed 刷新时更新，
  /// 不受收藏同步单独拉取文章的影响
  Future<int> getLastFeedSyncId() async {
    final db = await dbHelper.database;
    final result = await db.query(
      'metadata',
      where: 'key = ?',
      whereArgs: ['last_feed_sync_id'],
    );
    if (result.isNotEmpty) {
      return int.tryParse(result.first['value'] as String) ?? 0;
    }
    // 首次使用（如新安装后还没刷新过），回退到 0
    return 0;
  }

  /// 更新 feed 批量刷新的最大 article_id
  Future<void> setLastFeedSyncId(int id) async {
    final db = await dbHelper.database;
    await db.insert('metadata', {
      'key': 'last_feed_sync_id',
      'value': id.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> getMaxArticleId() async {
    final db = await dbHelper.database;
    final result = await db.rawQuery(
      'SELECT MAX(${Article.colId}) as max_id FROM ${Article.tableArticles}',
    );
    final maxId = result.first['max_id'] as int?;
    return maxId ?? 0;
  }

  Future<Set<int>> getFavoriteArticleIds() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      Article.tableArticles,
      columns: [Article.colId],
      where: '${Article.colIsFavorite} = ?',
      whereArgs: [1],
    );
    return maps.map((map) => map[Article.colId] as int).toSet();
  }

  /// 更新文章的缓存图片路径
  Future<int> updateCachePath(int articleId, String cachePath) async {
    final db = await dbHelper.database;
    return await db.update(
      Article.tableArticles,
      {Article.colGACachePath: cachePath},
      where: '${Article.colId} = ?',
      whereArgs: [articleId],
    );
  }

  /// 搜索文章（按标题、摘要、期刊名模糊匹配），同时应用 filter 筛选条件
  Future<List<Article>> searchArticles(
    String query, {
    int limit = 50,
    int offset = 0,
    ArticleFilter filter = ArticleFilter.empty,
  }) async {
    final db = await dbHelper.database;
    final pattern = '%$query%';
    // 搜索条件作为基础 WHERE，其余筛选条件追加在后
    final q = _buildFilterQuery(
      filter,
      baseWhere:
          '(${Article.colSummary} LIKE ? OR ${Article.colTitle} LIKE ? OR ${Article.colJournalName} LIKE ?)',
      baseArgs: [pattern, pattern, pattern],
    );
    final maps = await db.query(
      Article.tableArticles,
      where: q.where,
      whereArgs: q.whereArgs,
      orderBy: q.orderBy,
      limit: limit,
      offset: offset,
    );
    return maps.map((map) => Article.fromMap(map)).toList();
  }

  /// 获取所有没有缓存路径但有远程图片 URL 的文章
  Future<List<Map<String, dynamic>>> getUncachedImageArticles({
    int limit = 50,
  }) async {
    final db = await dbHelper.database;
    return await db.query(
      Article.tableArticles,
      columns: [Article.colId, Article.colGAUrl, Article.colGACachePath],
      where:
          '${Article.colGAUrl} IS NOT NULL AND ${Article.colGAUrl} != ? '
          'AND (${Article.colGACachePath} IS NULL OR ${Article.colGACachePath} = ?)',
      whereArgs: ['', ''],
      limit: limit,
      orderBy: '${Article.colId} DESC',
    );
  }

  /// 清空所有文章数据和同步队列
  Future<void> clearAll() async {
    final db = await dbHelper.database;
    await db.delete(Article.tableArticles);
    await db.delete('sync_queue');
    await db.delete('metadata');
  }

  /// 返回当前 articles 表中实际出现的期刊（DISTINCT），供筛选面板使用。
  /// 只从 articles 里读取，不依赖 journals 表，保证筛选范围
  /// 和用户真实订阅的内容一致。
  Future<List<({int id, String name, String abbr})>>
  getDistinctJournalsInArticles() async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT ${Article.colJournalId}, '
      '${Article.colJournalName}, '
      '${Article.colJournalAbbr} '
      'FROM ${Article.tableArticles} '
      'ORDER BY ${Article.colJournalAbbr} ASC',
    );
    return rows
        .map(
          (r) => (
            id: r[Article.colJournalId] as int,
            name: r[Article.colJournalName] as String,
            abbr: r[Article.colJournalAbbr] as String,
          ),
        )
        .toList();
  }

  /// 返回当前 articles 表中所有出现过的话题标签（maintag + subtags 合集）。
  ///
  /// - maintag 直接 DISTINCT 查询
  ///   在 Dart 侧解析后合并到结果中
  /// - 去重、排序后返回
  Future<List<String>> getDistinctTagsInArticles() async {
    final db = await dbHelper.database;

    // 1. 取所有非空 maintag
    final maintagRows = await db.rawQuery(
      'SELECT DISTINCT ${Article.colMaintag} '
      'FROM ${Article.tableArticles} '
      'WHERE ${Article.colMaintag} IS NOT NULL '
      "AND ${Article.colMaintag} != ''",
    );

    final tagSet = <String>{};

    for (final row in maintagRows) {
      final v = row[Article.colMaintag];
      if (v is String && v.isNotEmpty) tagSet.add(v);
    }

    final result = tagSet.toList()..sort();
    return result;
  }

  // ── Query 构建工具 ──

  /// 将 [ArticleFilter] 转换为 SQLite WHERE 子句、绑定参数和 ORDER BY 字符串。
  ///
  /// [baseWhere] / [baseArgs]：调用方固定需要的前置条件（如 is_favorite=1），
  /// filter 中的条件会 AND 追加在后面。
  ({String where, List<dynamic> whereArgs, String orderBy}) _buildFilterQuery(
    ArticleFilter filter, {
    String? baseWhere,
    List<dynamic>? baseArgs,
  }) {
    final conditions = <String>[];
    final args = <dynamic>[];

    // 1. 先把调用方传入的固定基础条件放进去
    if (baseWhere != null && baseWhere.isNotEmpty) {
      conditions.add(baseWhere);
      if (baseArgs != null) args.addAll(baseArgs);
    }

    // 2. 阅读状态
    //    all → 不添加任何条件
    //    read → is_read = 1
    //    unread → is_read = 0
    switch (filter.readStatus) {
      case ReadStatusFilter.read:
        conditions.add('${Article.colIsRead} = ?');
        args.add(1);
      case ReadStatusFilter.unread:
        conditions.add('${Article.colIsRead} = ?');
        args.add(0);
      case ReadStatusFilter.all:
        break;
    }

    // 3. 期刊 ID 集合 → journal_id IN (?, ?, …)
    if (filter.journalIds.isNotEmpty) {
      final placeholders = List.filled(
        filter.journalIds.length,
        '?',
      ).join(', ');
      conditions.add('${Article.colJournalId} IN ($placeholders)');
      args.addAll(filter.journalIds);
    }

    // 4. 话题标签
    //    maintag 列直接等值匹配；subtags 列以 JSON 数组字符串形式存储（如 ["Bio","Chem"]），
    //    使用 LIKE '%"tag"%' 模糊匹配，准确率足够且无需额外 JSON 函数。
    //    多个 tag 之间取 OR（"命中任意一个即可"）。
    if (filter.tags.isNotEmpty) {
      final tagClauses = filter.tags
          .map(
            (_) =>
                '(${Article.colMaintag} = ? OR ${Article.colSubtags} LIKE ?)',
          )
          .join(' OR ');
      conditions.add('($tagClauses)');
      for (final tag in filter.tags) {
        args.add(tag);
        args.add('%"$tag"%');
      }
    }

    // 5. 排序
    //    byId → article_id DESC（与后端推送顺序一致，新推送的在前）
    //    byDate → published_date DESC（按论文实际发表日期降序）
    final orderBy = filter.sortOrder == SortOrder.byDate
        ? '${Article.colPublishedDate} DESC'
        : '${Article.colId} DESC';

    return (where: conditions.join(' AND '), whereArgs: args, orderBy: orderBy);
  }
}
