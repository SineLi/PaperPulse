import 'dart:developer';

import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'schema.dart';

class DatabaseHelper {
  Database? _database;
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbFileDir = join(
      (await getApplicationDocumentsDirectory()).path,
      'app_database.db',
    );
    final db = await openDatabase(
      dbFileDir,
      version: 4,
      onCreate: (db, version) async {
        await db.execute(createArticlesTable);
        await db.execute(createJournalsTable);
        await db.execute(createSyncQueueTable);
        await db.execute(createUserSubscriptionsTable);
        await db.execute(createMetadataTable);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(createMetadataTable);
          // 用当前 max article_id 初始化 last_feed_sync_id，保证向后兼容
          final result = await db.rawQuery(
            'SELECT MAX(article_id) as max_id FROM articles',
          );
          final maxId = result.first['max_id'] as int? ?? 0;
          await db.insert('metadata', {
            'key': 'last_feed_sync_id',
            'value': maxId.toString(),
          });
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE articles ADD COLUMN graphical_abstract_fallback_url TEXT',
          );
        }
      },
    );
    return db;
  }

  Future<void> resetDatabaseForDev() async {
    final db = await database;
    await db.execute('DROP TABLE IF EXISTS articles');
    await db.execute('DROP TABLE IF EXISTS journals');
    await db.execute('DROP TABLE IF EXISTS sync_queue');
    await db.execute('DROP TABLE IF EXISTS user_subscriptions');
    await db.execute('DROP TABLE IF EXISTS metadata');
    await db.execute(createArticlesTable);
    await db.execute(createJournalsTable);
    await db.execute(createSyncQueueTable);
    await db.execute(createUserSubscriptionsTable);
    await db.execute(createMetadataTable);
  }

  Future<void> dbCheck() async {
    final db = await database;
    final result = await db.rawQuery("SELECT * FROM articles;");
    log('$result', name: 'DatabaseHelper');
  }
}
