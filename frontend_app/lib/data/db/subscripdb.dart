import 'database.dart';
import 'package:sqflite/sqflite.dart';

class SubscriptionDatabaseIO {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  Future<int> removeSubscription(int journalId) async {
    final db = await dbHelper.database;
    return await db.delete(
      'user_subscriptions',
      where: 'journal_id = ?',
      whereArgs: [journalId],
    );
  }

  Future<int> addSubscriptions(List<int> journalIds) async {
    final db = await dbHelper.database;
    final batch = db.batch();
    for (var journalId in journalIds) {
      batch.insert('user_subscriptions', {
        'journal_id': journalId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    return journalIds.length;
  }

  Future<int> removeAll(List<int> journalIds) async {
    if (journalIds.isEmpty) return 0;
    final db = await dbHelper.database;
    final batch = db.batch();
    for (var journalId in journalIds) {
      batch.delete(
        'user_subscriptions',
        where: 'journal_id = ?',
        whereArgs: [journalId],
      );
    }
    await batch.commit(noResult: true);
    return journalIds.length;
  }

  Future<void> replaceAll(List<int> journalIds) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('user_subscriptions');
      final batch = txn.batch();
      for (var journalId in journalIds) {
        batch.insert('user_subscriptions', {
          'journal_id': journalId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<int>> getSubscribedJournalIds() async {
    final db = await dbHelper.database;
    final maps = await db.query('user_subscriptions');
    return maps.map((map) => map['journal_id'] as int).toList();
  }
}
