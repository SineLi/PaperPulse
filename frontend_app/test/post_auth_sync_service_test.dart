import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/data/repositories/feed_repo.dart';
import 'package:frontend_app/data/repositories/journal_repo.dart';
import 'package:frontend_app/data/repositories/user_repo.dart';
import 'package:frontend_app/data/service/post_auth_sync_service.dart';
import 'package:frontend_app/data/service/sync_service.dart';

class _FakeJournalRepo implements JournalRepo {
  @override
  Future<JournalCatalogSyncResult> syncJournalsIfNeeded({
    int pageSize = 1000,
    int maxAttempts = 2,
  }) async => const JournalCatalogSyncResult(changed: true, journalCount: 2);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BlockingUserRepo implements UserRepo {
  final started = Completer<void>();
  final finish = Completer<int>();

  @override
  Future<int> syncSubscribedJournalIds() {
    if (!started.isCompleted) started.complete();
    return finish.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFeedRepo implements FeedRepo {
  @override
  Future<int> refreshArticles({int pageSize = 1000}) async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSyncService implements SyncService {
  @override
  Future<void> pullStatus({int pageSize = 1000}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'signals catalog replacement before the remaining sync completes',
    () async {
      final userRepo = _BlockingUserRepo();
      final service = PostAuthSyncService(
        journalRepo: _FakeJournalRepo(),
        userRepo: userRepo,
        feedRepo: _FakeFeedRepo(),
        syncService: _FakeSyncService(),
      );
      addTearDown(service.dispose);

      final sync = service.syncAfterAuth();
      await userRepo.started.future;

      expect(service.journalCatalogRefreshCount, 1);
      expect(service.completedSyncCount, 0);

      userRepo.finish.complete(0);
      await sync;
      await Future<void>.delayed(Duration.zero);

      expect(service.completedSyncCount, 1);
    },
  );
}
