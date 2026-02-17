import 'database.dart';
import '../models/article.dart';
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

  Future<List<Article>> getArticles(int limit, int offset) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      Article.tableArticles,
      limit: limit,
      offset: offset,
      orderBy: '${Article.colId} DESC',
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
  }) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      Article.tableArticles,
      where: '${Article.colIsFavorite} = ?',
      whereArgs: [1],
      orderBy: '${Article.colId} DESC',
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

  /// 搜索文章（按标题、摘要、期刊名模糊匹配）
  Future<List<Article>> searchArticles(
    String query, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await dbHelper.database;
    final pattern = '%$query%';
    final maps = await db.query(
      Article.tableArticles,
      where:
          '${Article.colTitle} LIKE ? OR ${Article.colAbs} LIKE ? OR ${Article.colJournalName} LIKE ?',
      whereArgs: [pattern, pattern, pattern],
      orderBy: '${Article.colId} DESC',
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
}
