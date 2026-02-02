import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';

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

import 'pages/login_page.dart';
import 'pages/feed_page.dart';

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

  runApp(MyApp(authServices: authServices));
}

class MyApp extends StatelessWidget {
  final AuthServices authServices;

  const MyApp({super.key, required this.authServices});

  static const _defaultColorSeed = Colors.blue;

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme lightColorScheme;
        ColorScheme darkColorScheme;

        if (lightDynamic != null && darkDynamic != null) {
          lightColorScheme = lightDynamic.harmonized();
          darkColorScheme = darkDynamic.harmonized();
        } else {
          lightColorScheme = ColorScheme.fromSeed(seedColor: _defaultColorSeed);
          darkColorScheme = ColorScheme.fromSeed(
            seedColor: _defaultColorSeed,
            brightness: Brightness.dark,
          );
        }

        return Provider<AuthServices>.value(
          value: authServices,
          child: MaterialApp(
            title: 'Flutter Demo',
            theme: ThemeData(primarySwatch: Colors.blue),
            home: LoginPage(),
            routes: {
              '/feed': (context) => const FeedPage(username: 'placeholder'),
            },
          ),
        );
      },
    );
  }
}
