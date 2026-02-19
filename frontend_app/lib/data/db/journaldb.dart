import 'database.dart';
import '../models/journal.dart';
import 'package:sqflite/sqflite.dart';

class JournalDatabaseIO {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  Future<int> addJournal(Journal journal) async {
    final db = await dbHelper.database;
    return await db.insert(
      Journal.tableJournals,
      journal.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Journal?> getJournal(int id) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      Journal.tableJournals,
      where: '${Journal.colId} = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Journal.fromMap(maps.first);
    } else {
      return null;
    }
  }

  Future<List<Journal>> getJournals({int limit = 100, int offset = 0}) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      Journal.tableJournals,
      limit: limit,
      offset: offset,
      orderBy: '${Journal.colId} DESC',
    );
    return maps.map((map) => Journal.fromMap(map)).toList();
  }

  Future<Journal> getJournalByID(int journalId) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      Journal.tableJournals,
      where: '${Journal.colId} = ?',
      whereArgs: [journalId],
    );
    if (maps.isNotEmpty) {
      return Journal.fromMap(maps.first);
    } else {
      throw Exception('Journal with ID $journalId not found');
    }
  }

  Future<int> getJournalCount() async {
    final db = await dbHelper.database;
    final result = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM ${Journal.tableJournals}'),
    );
    return result ?? 0;
  }

  Future<void> addJournals(List<Journal> journals) async {
    final db = await dbHelper.database;
    final batch = db.batch();
    for (var journal in journals) {
      batch.insert(
        Journal.tableJournals,
        journal.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
