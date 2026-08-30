import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
import 'data/service/backend_status_service.dart';
import 'data/service/journal_service.dart';
import 'data/service/post_auth_sync_service.dart';
import 'data/service/sync_service.dart';
import 'data/service/user_services.dart';
import 'data/service/image_cache_service.dart';
import 'navigation/tab_scroll_registry.dart';
import 'settings/settings_controller.dart';
import 'router/app_router.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  GoRouter.optionURLReflectsImperativeAPIs = true;

  final settingsController = SettingsController(SettingStorage());
  await settingsController.load();
  final packageInfo = await PackageInfo.fromPlatform();
  final backendStatusController = BackendStatusController(
    BackendStatusService(),
    clientVersion: packageInfo.version,
  );
  final configuredBaseUrl = settingsController.setting.baseURL.trim();
  if (configuredBaseUrl.isNotEmpty) {
    unawaited(backendStatusController.checkSilently(configuredBaseUrl));
  }

  final authStorage = AuthStorage();
  final apiClient = ApiClient(
    baseUrl: settingsController.setting.baseURL,
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

  final postAuthSyncService = PostAuthSyncService(
    journalRepo: journalRepo,
    userRepo: userRepo,
    feedRepo: feedRepo,
    syncService: syncService,
  );
  final tabScrollRegistry = TabScrollRegistry();

  // Initialize wifiOnly from loaded settings, then keep in sync via listener.
  // The listener is intentionally never removed: all three objects
  // (settingsController, apiClient, imageCacheService) share the same
  // application lifetime, so there is no risk of a memory leak.
  imageCacheService.wifiOnly = settingsController.setting.wifiOnlyImages;
  imageCacheService.baseUrl = settingsController.setting.baseURL;
  settingsController.addListener(() {
    final url = settingsController.setting.baseURL.trim();
    if (url.isNotEmpty) {
      apiClient.baseUrl = url;
    }
    imageCacheService.baseUrl = settingsController.setting.baseURL;
    imageCacheService.wifiOnly = settingsController.setting.wifiOnlyImages;
  });

  runApp(
    MyApp(
      settingsController: settingsController,
      backendStatusController: backendStatusController,
      authServices: authServices,
      articleDb: articleDb,
      feedRepo: feedRepo,
      journalRepo: journalRepo,
      userRepo: userRepo,
      syncService: syncService,
      imageCacheService: imageCacheService,
      postAuthSyncService: postAuthSyncService,
      tabScrollRegistry: tabScrollRegistry,
    ),
  );
}

class MyApp extends StatelessWidget {
  final SettingsController settingsController;
  final BackendStatusController backendStatusController;
  final AuthServices authServices;
  final ArticleDatabaseIO articleDb;
  final FeedRepo feedRepo;
  final JournalRepo journalRepo;
  final UserRepo userRepo;
  final SyncService syncService;
  final ImageCacheService imageCacheService;
  final PostAuthSyncService postAuthSyncService;
  final TabScrollRegistry tabScrollRegistry;
  const MyApp({
    super.key,
    required this.settingsController,
    required this.backendStatusController,
    required this.authServices,
    required this.articleDb,
    required this.feedRepo,
    required this.journalRepo,
    required this.userRepo,
    required this.syncService,
    required this.imageCacheService,
    required this.postAuthSyncService,
    required this.tabScrollRegistry,
  });

  static const _defaultColorSeed = Colors.blue;
  static const _amoledBlack = Color(0xFF000000);
  static const _amoledRaised = Color(0xFF0D0D0D);
  static const _appFontFamily = 'AppSans';
  static const _appFontFallback = <String>['AppCJK'];
  static final _router = createAppRouter();

  ColorScheme _withAmoledSurfaces(ColorScheme base) {
    return base.copyWith(
      surface: _amoledBlack,
      surfaceDim: _amoledBlack,
      surfaceContainerLowest: _amoledBlack,
      surfaceContainerLow: _amoledBlack,
      surfaceContainer: _amoledBlack,
      surfaceContainerHigh: _amoledBlack,
      surfaceContainerHighest: _amoledRaised,
      surfaceBright: _amoledRaised,
      surfaceTint: Colors.transparent,
    );
  }

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

        return ChangeNotifierProvider<SettingsController>.value(
          value: settingsController,
          child: ChangeNotifierProvider<BackendStatusController>.value(
            value: backendStatusController,
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
                        child:
                            ChangeNotifierProvider<PostAuthSyncService>.value(
                              value: postAuthSyncService,
                              child: Provider<ImageCacheService>.value(
                                value: imageCacheService,
                                child: Provider<TabScrollRegistry>.value(
                                  value: tabScrollRegistry,
                                  child: Consumer<SettingsController>(
                                    builder: (context, settingsCtrl, _) {
                                      final amoledEnabled =
                                          settingsCtrl.setting.amoled;
                                      final effectiveDarkColorScheme =
                                          amoledEnabled
                                          ? _withAmoledSurfaces(darkColorScheme)
                                          : darkColorScheme;
                                      return MaterialApp.router(
                                        title: 'PaperPulse',
                                        routerConfig: _router,
                                        theme: ThemeData(
                                          platform: TargetPlatform.android,
                                          colorScheme: lightColorScheme,
                                          useMaterial3: true,
                                          snackBarTheme: snackBarTheme,
                                          fontFamily: _appFontFamily,
                                          fontFamilyFallback: _appFontFallback,
                                        ),
                                        darkTheme: ThemeData(
                                          colorScheme: effectiveDarkColorScheme,
                                          useMaterial3: true,
                                          snackBarTheme: snackBarTheme,
                                          platform: TargetPlatform.android,
                                          fontFamily: _appFontFamily,
                                          fontFamilyFallback: _appFontFallback,
                                          scaffoldBackgroundColor: amoledEnabled
                                              ? _amoledBlack
                                              : null,
                                          canvasColor: amoledEnabled
                                              ? _amoledBlack
                                              : null,
                                          cardColor: amoledEnabled
                                              ? _amoledBlack
                                              : null,
                                          appBarTheme: AppBarTheme(
                                            backgroundColor: amoledEnabled
                                                ? _amoledBlack
                                                : null,
                                            surfaceTintColor: amoledEnabled
                                                ? Colors.transparent
                                                : null,
                                          ),
                                        ),
                                        themeMode: context
                                            .watch<SettingsController>()
                                            .themeMode,
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
              ),
            ),
          ),
        );
      },
    );
  }
}
