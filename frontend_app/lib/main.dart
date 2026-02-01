import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/api/client.dart';
import 'data/auth/auth_services.dart';
import 'data/auth/auth_storage.dart';
import 'data/db/articledb.dart';
import 'data/db/subscripdb.dart';
import 'data/db/syncdb.dart';
import 'data/repositories/feed_repo.dart';
import 'data/repositories/user_repo.dart';
import 'data/service/feed_service.dart';
import 'data/service/sync_service.dart';
import 'data/service/user_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final authStorage = AuthStorage();
  final apiClient = ApiClient(
    baseUrl: 'http://10.0.2.2:8000',
    authStorage: authStorage,
  );

  final userServices = UserServices(apiClient: apiClient);
  final authServices = AuthServices(
    apiClient: apiClient,
    authStorage: authStorage,
    userServices: userServices,
  );

  final articleDb = ArticleDatabaseIO();
  final feedService = FeedService(apiClient: apiClient);
  final feedRepo = FeedRepo(
    feedService: feedService,
    articleDatabaseIO: articleDb,
  );

  final syncDb = SyncDatabaseIO();
  final syncService = SyncService(
    apiClient: apiClient,
    syncDatabase: syncDb,
    articleDatabase: articleDb,
  );

  final subscriptionDb = SubscriptionDatabaseIO();
  final userRepo = UserRepo(
    userServices: userServices,
    subscriptionDatabaseIO: subscriptionDb,
    feedRepo: feedRepo,
  );

  runApp(Placeholder());
}
