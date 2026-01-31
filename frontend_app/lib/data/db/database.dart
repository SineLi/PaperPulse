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
      version: 1,
      onCreate: (db, version) async {
        await db.execute(createArticlesTable);
        await db.execute(createJournalsTable);
        await db.execute(createSyncQueueTable);
        await db.execute(createUserSubscriptionsTable);
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
    await db.execute(createArticlesTable);
    await db.execute(createJournalsTable);
    await db.execute(createSyncQueueTable);
    await db.execute(createUserSubscriptionsTable);
  }

  Future<void> dbCheck() async {
    final db = await database;
    final result = await db.rawQuery("SELECT * FROM articles;");
    print(result);
  }
}
