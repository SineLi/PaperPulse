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
      conflictAlgorithm: ConflictAlgorithm.replace,
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
        conflictAlgorithm: ConflictAlgorithm.replace,
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
}
