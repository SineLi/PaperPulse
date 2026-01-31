import '../service/user_services.dart';
import '../repositories/feed_repo.dart';
import '../db/subscripdb.dart';

class UserRepo {
  final UserServices _userServices;
  final SubscriptionDatabaseIO _subscriptionDatabaseIO;
  final FeedRepo _feedRepo;

  UserRepo({
    required UserServices userServices,
    required SubscriptionDatabaseIO subscriptionDatabaseIO,
    required FeedRepo feedRepo,
  }) : _userServices = userServices,
       _subscriptionDatabaseIO = subscriptionDatabaseIO,
       _feedRepo = feedRepo;

  Future<List<int>> fetchSubscribedJournalIds() async {
    return await _subscriptionDatabaseIO.getSubscribedJournalIds();
  }

  Future<int> syncSubscribedJournalIds() async {
    final remoteJournalIds = await _userServices.fetchSubscribedJournalIds();
    await _subscriptionDatabaseIO.replaceAll(remoteJournalIds);
    return remoteJournalIds.length;
  }

  Future<void> followJournal(int journalId) async {
    await _userServices.followJournal(journalId);
    await _subscriptionDatabaseIO.addSubscriptions([journalId]);
    _feedRepo.refreshArticles();
  }

  Future<void> unfollowJournal(int journalId) async {
    await _userServices.unfollowJournal(journalId);
    await _subscriptionDatabaseIO.removeSubscription(journalId);
    _feedRepo.refreshArticles();
  }
}
