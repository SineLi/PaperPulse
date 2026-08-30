import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/data/auth/auth_services.dart';
import 'package:frontend_app/data/models/article.dart';
import 'package:frontend_app/data/models/article_filter.dart';
import 'package:frontend_app/data/repositories/feed_repo.dart';
import 'package:frontend_app/data/service/post_auth_sync_service.dart';
import 'package:frontend_app/data/service/sync_service.dart';
import 'package:frontend_app/navigation/tab_scroll_registry.dart';
import 'package:frontend_app/pages/fav_page.dart';
import 'package:frontend_app/settings/feed_card_style.dart';
import 'package:frontend_app/settings/settings_controller.dart';
import 'package:frontend_app/widgets/article_list_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('favorites follows the selected feed card style', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.baseURL': 'https://example.test',
    });
    final settingsController = SettingsController(SettingStorage());
    await settingsController.load();
    final authServices = _FakeAuthServices();
    final postAuthSyncService = _FakePostAuthSyncService();
    addTearDown(settingsController.dispose);
    addTearDown(authServices.dispose);
    addTearDown(postAuthSyncService.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<FeedRepo>.value(value: _FakeFeedRepo()),
          Provider<SyncService>.value(value: _FakeSyncService()),
          Provider<TabScrollRegistry>(create: (_) => TabScrollRegistry()),
          ChangeNotifierProvider<AuthServices>.value(value: authServices),
          ChangeNotifierProvider<PostAuthSyncService>.value(
            value: postAuthSyncService,
          ),
          ChangeNotifierProvider<SettingsController>.value(
            value: settingsController,
          ),
        ],
        child: const MaterialApp(home: FavPage()),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<ArticleListPage>(find.byType(ArticleListPage)).cardStyle,
      FeedCardStyle.masonry,
    );

    await settingsController.updateFeedCardStyle(FeedCardStyle.compact);
    await tester.pump();

    final favoritesList = tester.widget<ArticleListPage>(
      find.byType(ArticleListPage),
    );
    expect(favoritesList.cardStyle, FeedCardStyle.compact);
    expect(favoritesList.dimReadArticles, isFalse);
  });
}

class _FakeFeedRepo implements FeedRepo {
  @override
  Future<List<Article>> getLocalFavoriteArticles({
    int limit = 50,
    int offset = 0,
    ArticleFilter filter = ArticleFilter.empty,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSyncService implements SyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthServices extends ChangeNotifier implements AuthServices {
  @override
  bool get isLoggedIn => true;

  @override
  Future<bool> hasToken() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePostAuthSyncService extends ChangeNotifier
    implements PostAuthSyncService {
  @override
  int get completedSyncCount => 0;

  @override
  bool get isSyncing => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
