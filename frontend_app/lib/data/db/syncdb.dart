import 'database.dart';

class SyncDatabaseIO {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  Future<int> addSyncAction(int articleId, String action) async {
    final db = await dbHelper.database;
    return await db.insert('sync_queue', {
      'article_id': articleId,
      'action': action,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
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
    final db = await dbHelper.database;
    final batch = db.batch();
    for (var id in ids) {
      batch.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }
}
