import '../service/journal_service.dart';
import '../db/journaldb.dart';
import '../models/journal.dart';

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
  }) async {
    return await _journalDatabaseIO.getJournals(limit: limit, offset: offset);
  }

  Future<int> syncJournalsEmpty({int pageSize = 1000}) async {
    final localCount = await _journalDatabaseIO.getJournalCount();
    if (localCount > 0) {
      return 0;
    }

    int totalAdded = 0;

    for (var offset = 0; ; offset += pageSize) {
      final journals = await _journalService.fetchJournals(
        limit: pageSize,
        offset: offset,
      );

      if (journals.isEmpty) {
        break;
      }

      await _journalDatabaseIO.addJournals(journals);
      totalAdded += journals.length;

      if (journals.length < pageSize) {
        // Last batch fetched
        break;
      }
    }

    return totalAdded;
  }
}
