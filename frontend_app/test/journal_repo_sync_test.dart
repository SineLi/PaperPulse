import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/data/api/client.dart';
import 'package:frontend_app/data/db/journaldb.dart';
import 'package:frontend_app/data/models/journal.dart';
import 'package:frontend_app/data/repositories/journal_repo.dart';
import 'package:frontend_app/data/service/journal_service.dart';

class _FakeJournalService extends JournalService {
  _FakeJournalService()
    : super(
        apiClient: ApiClient(
          baseUrl: 'https://example.test',
          authStorage: null,
        ),
      );

  final List<JournalCatalogStatus> statuses = [];
  final Map<int, List<Journal>> pages = {};
  int statusCalls = 0;
  int journalCalls = 0;

  @override
  Future<JournalCatalogStatus> fetchCatalogStatus() async {
    return statuses[statusCalls++];
  }

  @override
  Future<List<Journal>> fetchJournals({int limit = 100, int offset = 0}) async {
    journalCalls += 1;
    return pages[offset] ?? [];
  }
}

class _FakeJournalDatabase extends JournalDatabaseIO {
  int count = 0;
  String? revision;
  List<Journal>? replacement;
  String? replacementRevision;

  @override
  Future<int> getJournalCount() async => count;

  @override
  Future<String?> getCatalogRevision() async => revision;

  @override
  Future<void> replaceJournals(
    List<Journal> journals, {
    required String revision,
  }) async {
    replacement = List.of(journals);
    replacementRevision = revision;
  }
}

Journal _journal(int id) =>
    Journal(journalId: id, name: 'Journal $id', abbreviation: 'J$id');

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'https://example.test', authStorage: null);

  String? endpoint;

  @override
  Future<Map<String, dynamic>> getJson(String endpoint) async {
    this.endpoint = endpoint;
    return {'revision': '12', 'count': 34};
  }
}

void main() {
  test('journal service reads the dedicated catalog status endpoint', () async {
    final apiClient = _FakeApiClient();
    final service = JournalService(apiClient: apiClient);

    final status = await service.fetchCatalogStatus();

    expect(apiClient.endpoint, '/journals/status');
    expect(status.revision, '12');
    expect(status.count, 34);
  });

  test(
    'skips catalog download when revision and count are unchanged',
    () async {
      final service = _FakeJournalService()
        ..statuses.add(const JournalCatalogStatus(revision: '7', count: 2));
      final database = _FakeJournalDatabase()
        ..count = 2
        ..revision = '7';
      final repo = JournalRepo(
        journalService: service,
        journalDatabaseIO: database,
      );

      final synced = await repo.syncJournalsIfNeeded(pageSize: 2);

      expect(synced, 0);
      expect(service.journalCalls, 0);
      expect(database.replacement, isNull);
    },
  );

  test(
    'atomically replaces local catalog when backend revision changes',
    () async {
      final service = _FakeJournalService()
        ..statuses.addAll(const [
          JournalCatalogStatus(revision: '8', count: 3),
          JournalCatalogStatus(revision: '8', count: 3),
        ])
        ..pages[0] = [_journal(1), _journal(2)]
        ..pages[2] = [_journal(3)];
      final database = _FakeJournalDatabase()
        ..count = 4
        ..revision = '7';
      final repo = JournalRepo(
        journalService: service,
        journalDatabaseIO: database,
      );

      final synced = await repo.syncJournalsIfNeeded(pageSize: 2);

      expect(synced, 3);
      expect(database.replacement?.map((journal) => journal.journalId), [
        1,
        2,
        3,
      ]);
      expect(database.replacementRevision, '8');
    },
  );

  test('does not replace local data when catalog keeps changing', () async {
    final service = _FakeJournalService()
      ..statuses.addAll(const [
        JournalCatalogStatus(revision: '8', count: 2),
        JournalCatalogStatus(revision: '9', count: 2),
        JournalCatalogStatus(revision: '10', count: 2),
      ])
      ..pages[0] = [_journal(1), _journal(2)]
      ..pages[2] = [];
    final database = _FakeJournalDatabase()
      ..count = 2
      ..revision = '7';
    final repo = JournalRepo(
      journalService: service,
      journalDatabaseIO: database,
    );

    await expectLater(
      repo.syncJournalsIfNeeded(pageSize: 2, maxAttempts: 2),
      throwsA(isA<StateError>()),
    );

    expect(database.replacement, isNull);
  });
}
