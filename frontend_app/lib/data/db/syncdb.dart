import 'database.dart';
import 'package:sqflite/sqflite.dart';

class SyncDatabaseIO {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  Future<int> addSyncAction(int articleId, String action) async {
    final db = await dbHelper.database;
    return await db.insert('sync_queue', {
      'article_id': articleId,
      'action': action,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, Object?>>> getPendingSyncActions({
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await dbHelper.database;
    return await db.query(
      'sync_queue',
      orderBy: 'timestamp ASC',
      limit: limit,
      offset: offset,
    );
  }

  Future<void> removeSyncActions(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await dbHelper.database;
    final batch = db.batch();
    for (var id in ids) {
      batch.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  /// 清理旧版本可能遗留的收藏队列动作，避免直传结果随后被覆盖。
  Future<void> removeFavoriteActionsForArticle(int articleId) async {
    final db = await dbHelper.database;
    await db.delete(
      'sync_queue',
      where: 'article_id = ? AND action IN (?, ?)',
      whereArgs: [articleId, 'favorite', 'unfavorite'],
    );
  }
}
