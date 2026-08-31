import '../service/journal_service.dart';
import '../db/journaldb.dart';
import '../models/journal.dart';
import '../models/journal_filter.dart';

class JournalCatalogSyncResult {
  final bool changed;
  final int journalCount;

  const JournalCatalogSyncResult({
    required this.changed,
    required this.journalCount,
  });
}

class JournalRepo {
  final JournalService _journalService;
  final JournalDatabaseIO _journalDatabaseIO;

  JournalRepo({
    required JournalService journalService,
    required JournalDatabaseIO journalDatabaseIO,
  }) : _journalService = journalService,
       _journalDatabaseIO = journalDatabaseIO;

  Future<List<Journal>> getLocalJournals({
    int limit = 50,
    int offset = 0,
    JournalFilter filter = JournalFilter.empty,
  }) async {
    return await _journalDatabaseIO.getJournals(
      limit: limit,
      offset: offset,
      filter: filter,
    );
  }

  Future<List<String>> getFilterablePublishers() async {
    return await _journalDatabaseIO.getDistinctPublishers();
  }

  Future<List<String>> getFilterableCasCategories() async {
    return await _journalDatabaseIO.getDistinctCasCategories();
  }

  Future<Journal?> getLocalJournalById(int journalId) async {
    return await _journalDatabaseIO.getJournal(journalId);
  }

  /// 搜索本地期刊（按名称/缩写/出版商模糊匹配）
  Future<List<Journal>> searchLocalJournals(
    String query, {
    int limit = 50,
    int offset = 0,
  }) async {
    return await _journalDatabaseIO.searchJournals(
      query,
      limit: limit,
      offset: offset,
    );
  }

  Future<JournalCatalogSyncResult> syncJournalsIfNeeded({
    int pageSize = 1000,
    int maxAttempts = 2,
  }) async {
    if (pageSize <= 0) throw ArgumentError.value(pageSize, 'pageSize');
    if (maxAttempts <= 0) throw ArgumentError.value(maxAttempts, 'maxAttempts');

    final localCount = await _journalDatabaseIO.getJournalCount();
    final localRevision = await _journalDatabaseIO.getCatalogRevision();
    var expectedStatus = await _journalService.fetchCatalogStatus();
    if (localCount == expectedStatus.count &&
        localRevision == expectedStatus.revision) {
      return JournalCatalogSyncResult(changed: false, journalCount: localCount);
    }

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final journals = <Journal>[];

      for (var offset = 0; ; offset += pageSize) {
        final page = await _journalService.fetchJournals(
          limit: pageSize,
          offset: offset,
        );
        journals.addAll(page);

        if (page.length < pageSize) break;
      }

      final actualStatus = await _journalService.fetchCatalogStatus();
      final uniqueJournalCount = journals
          .map((journal) => journal.journalId)
          .toSet()
          .length;
      final isConsistent =
          actualStatus.revision == expectedStatus.revision &&
          journals.length == actualStatus.count &&
          uniqueJournalCount == actualStatus.count;
      if (isConsistent) {
        await _journalDatabaseIO.replaceJournals(
          journals,
          revision: actualStatus.revision,
        );
        return JournalCatalogSyncResult(
          changed: true,
          journalCount: journals.length,
        );
      }

      expectedStatus = actualStatus;
    }

    throw StateError(
      'Journal catalog changed repeatedly during synchronization',
    );
  }

  Future<int> syncJournalsEmpty({int pageSize = 1000}) async {
    final result = await syncJournalsIfNeeded(pageSize: pageSize);
    return result.changed ? result.journalCount : 0;
  }
}
