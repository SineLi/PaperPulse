import 'database.dart';
import '../models/journal.dart';
import '../models/journal_filter.dart';
import 'package:sqflite/sqflite.dart';

class JournalDatabaseIO {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;
  static const String _catalogRevisionKey = 'journal_catalog_revision';

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

  /// 构建期刊筛选的 WHERE 子句与排序
  ({String where, List whereArgs}) _buildJournalFilterQuery(
    JournalFilter filter, {
    String baseWhere = '',
    List baseArgs = const [],
  }) {
    final conditions = <String>[];
    final args = <dynamic>[...baseArgs];

    if (baseWhere.isNotEmpty) conditions.add(baseWhere);

    // 出版商多选
    if (filter.publishers.isNotEmpty) {
      final placeholders = List.filled(
        filter.publishers.length,
        '?',
      ).join(', ');
      conditions.add('${Journal.colPublisher} IN ($placeholders)');
      args.addAll(filter.publishers);
    }

    // SCI 收录
    if (filter.sciFilter == SciFilter.sci1) {
      conditions.add('${Journal.colSci} = 1');
    } else if (filter.sciFilter == SciFilter.sci2) {
      conditions.add('${Journal.colSci} = 2');
    } else if (filter.sciFilter == SciFilter.sci3) {
      conditions.add('${Journal.colSci} = 3');
    } else if (filter.sciFilter == SciFilter.sci4) {
      conditions.add('${Journal.colSci} = 4');
    } else if (filter.sciFilter == SciFilter.nonSci) {
      conditions.add('${Journal.colSci} = 0');
    }

    // CAS 分区多选（筛选值为学科名，如"化学"；DB 存储为"化学1区"，用 LIKE 前缀匹配）
    if (filter.casCategories.isNotEmpty) {
      final likeConditions = filter.casCategories
          .map((_) => '${Journal.colCASUp} LIKE ?')
          .join(' OR ');
      conditions.add('($likeConditions)');
      args.addAll(filter.casCategories.map((cat) => '$cat%'));
    }

    // 影响因子下限（ifMin == 0 表示不限）
    if (filter.ifMin > 0) {
      conditions.add('${Journal.colIf0} >= ?');
      args.add(filter.ifMin);
    }

    final where = conditions.join(' AND ');
    return (where: where, whereArgs: args);
  }

  Future<List<Journal>> getJournals({
    int limit = 100,
    int offset = 0,
    JournalFilter filter = JournalFilter.empty,
  }) async {
    final db = await dbHelper.database;
    final q = _buildJournalFilterQuery(filter);
    final maps = await db.query(
      Journal.tableJournals,
      where: q.where.isEmpty ? null : q.where,
      whereArgs: q.whereArgs.isEmpty ? null : q.whereArgs,
      limit: limit,
      offset: offset,
      orderBy: '${Journal.colId} ASC',
    );
    return maps.map((map) => Journal.fromMap(map)).toList();
  }

  /// 返回所有去重出版商名称（非空）
  Future<List<String>> getDistinctPublishers() async {
    final db = await dbHelper.database;
    final maps = await db.rawQuery(
      'SELECT DISTINCT ${Journal.colPublisher} FROM ${Journal.tableJournals} '
      "WHERE ${Journal.colPublisher} IS NOT NULL AND ${Journal.colPublisher} != '' "
      'ORDER BY ${Journal.colPublisher} ASC',
    );
    return maps.map((m) => m[Journal.colPublisher] as String).toList();
  }

  /// 返回所有去重 CAS 学科名（截掉末尾「数字+区」两个字符，如"化学1区"→"化学"）
  Future<List<String>> getDistinctCasCategories() async {
    final db = await dbHelper.database;
    final maps = await db.rawQuery(
      'SELECT DISTINCT SUBSTR(${Journal.colCASUp}, 1, LENGTH(${Journal.colCASUp}) - 2) AS cat '
      'FROM ${Journal.tableJournals} '
      "WHERE ${Journal.colCASUp} IS NOT NULL AND ${Journal.colCASUp} != '' "
      'ORDER BY cat ASC',
    );
    return maps.map((m) => m['cat'] as String).toList();
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

  Future<String?> getCatalogRevision() async {
    final db = await dbHelper.database;
    final rows = await db.query(
      'metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_catalogRevisionKey],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  /// 搜索期刊（按名称、缩写、出版商模糊匹配）
  Future<List<Journal>> searchJournals(
    String query, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await dbHelper.database;
    final pattern = '%$query%';
    final maps = await db.query(
      Journal.tableJournals,
      where:
          '${Journal.colName} LIKE ? OR ${Journal.colAbbreviation} LIKE ? OR ${Journal.colPublisher} LIKE ?',
      whereArgs: [pattern, pattern, pattern],
      orderBy: '${Journal.colId} ASC',
      limit: limit,
      offset: offset,
    );
    return maps.map((map) => Journal.fromMap(map)).toList();
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

  Future<void> replaceJournals(
    List<Journal> journals, {
    required String revision,
  }) async {
    final db = await dbHelper.database;
    await db.transaction((transaction) async {
      await transaction.delete(Journal.tableJournals);
      final batch = transaction.batch();
      for (final journal in journals) {
        batch.insert(
          Journal.tableJournals,
          journal.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      batch.insert('metadata', {
        'key': _catalogRevisionKey,
        'value': revision,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await batch.commit(noResult: true);
    });
  }
}
