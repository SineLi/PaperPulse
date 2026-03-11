import '../repositories/feed_repo.dart';
import '../repositories/journal_repo.dart';
import '../repositories/user_repo.dart';
import 'sync_service.dart';

class PostAuthSyncService {
  final JournalRepo _journalRepo;
  final UserRepo _userRepo;
  final FeedRepo _feedRepo;
  final SyncService _syncService;

  Future<void>? _syncInFlight;

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

    final future = _performSyncAfterAuth();
    _syncInFlight = future;
    future.whenComplete(() {
      if (identical(_syncInFlight, future)) {
        _syncInFlight = null;
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
}
