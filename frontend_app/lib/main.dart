import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'data/api/client.dart';
import 'data/auth/auth_services.dart';
import 'data/auth/auth_storage.dart';
import 'data/db/articledb.dart';
import 'data/db/journaldb.dart';
import 'data/db/syncdb.dart';
import 'data/db/subscripdb.dart';
import 'data/repositories/feed_repo.dart';
import 'data/repositories/journal_repo.dart';
import 'data/repositories/user_repo.dart';
import 'data/service/feed_service.dart';
import 'data/service/journal_service.dart';
import 'data/service/sync_service.dart';
import 'data/service/user_services.dart';
import 'data/service/image_cache_service.dart';
import 'data/repositories/user_repo.dart';

import 'pages/login_page.dart';
import 'pages/bootstrap_page.dart';
import 'pages/app_shell_page.dart';
import 'pages/setting_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final authStorage = AuthStorage();
  final apiClient = ApiClient(baseUrl: '', authStorage: authStorage);

  final userServices = UserServices(apiClient: apiClient);
  final authServices = AuthServices(
    apiClient: apiClient,
    authStorage: authStorage,
    userServices: userServices,
  );

  final articleDb = ArticleDatabaseIO();
  final feedService = FeedService(apiClient: apiClient);

  final journalDb = JournalDatabaseIO();
  final journalService = JournalService(apiClient: apiClient);
  final journalRepo = JournalRepo(
    journalService: journalService,
    journalDatabaseIO: journalDb,
  );

  final imageCacheService = ImageCacheService(articleDb: articleDb);

  final feedRepo = FeedRepo(
    feedService: feedService,
    articleDatabaseIO: articleDb,
    journalRepo: journalRepo,
    imageCacheService: imageCacheService,
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

  runApp(
    MyApp(
      authServices: authServices,
      articleDb: articleDb,
      feedRepo: feedRepo,
      journalRepo: journalRepo,
      userRepo: userRepo,
      syncService: syncService,
      imageCacheService: imageCacheService,
    ),
  );
}

class MyApp extends StatelessWidget {
  final AuthServices authServices;
  final ArticleDatabaseIO articleDb;
  final FeedRepo feedRepo;
  final JournalRepo journalRepo;
  final UserRepo userRepo;
  final SyncService syncService;
  final ImageCacheService imageCacheService;
  const MyApp({
    super.key,
    required this.authServices,
    required this.articleDb,
    required this.feedRepo,
    required this.journalRepo,
    required this.userRepo,
    required this.syncService,
    required this.imageCacheService,
  });

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

        final snackBarTheme = SnackBarThemeData(
          behavior: SnackBarBehavior.fixed,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
        );

        return ChangeNotifierProvider(
          create: (_) => SettingsController(SettingStorage())..load(),
          child: ChangeNotifierProvider<AuthServices>.value(
            value: authServices,
            child: Provider<ArticleDatabaseIO>.value(
              value: articleDb,
              child: Provider<JournalRepo>.value(
                value: journalRepo,
                child: Provider<UserRepo>.value(
                  value: userRepo,
                  child: Provider<FeedRepo>.value(
                    value: feedRepo,
                    child: Provider<SyncService>.value(
                      value: syncService,
                      child: Provider<ImageCacheService>.value(
                        value: imageCacheService,
                        child: Consumer<SettingsController>(
                          builder: (context, settingsCtrl, _) {
                            // 同步 Wi-Fi 专属下载设置到图片缓存服务
                            imageCacheService.wifiOnly =
                                settingsCtrl.setting.wifiOnlyImages;
                            return MaterialApp(
                              title: 'PaperPulse',
                              theme: ThemeData(
                                colorScheme: lightColorScheme,
                                useMaterial3: true,
                                snackBarTheme: snackBarTheme,
                              ),
                              darkTheme: ThemeData(
                                colorScheme: darkColorScheme,
                                useMaterial3: true,
                                snackBarTheme: snackBarTheme,
                              ),
                              themeMode: context
                                  .watch<SettingsController>()
                                  .themeMode,
                              home: const BootstrapPage(),
                              routes: {
                                '/feed': (context) => const AppShellPage(),
                                '/login': (context) => const LoginPage(),
                                '/settings': (context) => const SettingPage(),
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
