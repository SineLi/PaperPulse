import 'package:flutter/foundation.dart';

import '../repositories/feed_repo.dart';
import '../repositories/journal_repo.dart';
import '../repositories/user_repo.dart';
import 'sync_service.dart';

class PostAuthSyncService extends ChangeNotifier {
  final JournalRepo _journalRepo;
  final UserRepo _userRepo;
  final FeedRepo _feedRepo;
  final SyncService _syncService;

  Future<void>? _syncInFlight;
  bool _isSyncing = false;
  int _completedSyncCount = 0;

  bool get isSyncing => _isSyncing;
  int get completedSyncCount => _completedSyncCount;

  PostAuthSyncService({
    required JournalRepo journalRepo,
    required UserRepo userRepo,
    required FeedRepo feedRepo,
    required SyncService syncService,
  }) : _journalRepo = journalRepo,
       _userRepo = userRepo,
       _feedRepo = feedRepo,
       _syncService = syncService;

  Future<void> syncAfterAuth() {
    final inFlight = _syncInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    _setSyncing(true);
    final future = _performSyncAfterAuth();
    var didComplete = false;
    _syncInFlight = future;
    future
        .then((_) {
          didComplete = true;
        })
        .whenComplete(() {
          if (identical(_syncInFlight, future)) {
            _syncInFlight = null;
          }
          _setSyncing(false);
          if (didComplete) {
            _completedSyncCount += 1;
            notifyListeners();
          }
        });
    return future;
  }

  Future<void> _performSyncAfterAuth() async {
    await _journalRepo.syncJournalsEmpty();
    await _userRepo.syncSubscribedJournalIds();
    await _syncService.pullStatus();
    await _feedRepo.refreshArticles();
  }

  void _setSyncing(bool value) {
    if (_isSyncing == value) return;
    _isSyncing = value;
    notifyListeners();
  }
}
