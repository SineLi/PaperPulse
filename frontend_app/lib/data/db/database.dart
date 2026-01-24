import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'schema.dart';
import '../models/article.dart';

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
      },
    );
    return db;
  }

  Future<void> clearDatabase() async {
    final db = await database;
    await db.execute('DROP TABLE IF EXISTS articles');
    await db.execute('DROP TABLE IF EXISTS journals');
  }

  Future<void> dbCheck() async {
    final db = await database;
    final result = await db.rawQuery("SELECT * FROM articles;");
    print(result);
  }

  Future<int> addArticle(Article article) async {
    final db = await database;
    return await db.insert(
      Article.tableArticles,
      article.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Article?> getArticle(int id) async {
    final db = await database;
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
}
