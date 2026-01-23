import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'schema.dart' show createArticlesTable;

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
      },
    );
    return db;
  }

  Future<void> dbCheck() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='articles';",
    );
    print(result);
  }
}
