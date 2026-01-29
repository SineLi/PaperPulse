import 'package:flutter/widgets.dart';
import 'package:frontend_app/data/db/articledb.dart';
import 'data/auth/auth_services.dart';
import 'data/auth/auth_storage.dart';
import 'data/api/client.dart';
import 'data/service/feed_service.dart';
import 'data/service/sync_service.dart';
import 'data/db/syncdb.dart';

Future<void> main() async {
  print("Starting app...");
  WidgetsFlutterBinding.ensureInitialized();
  final authStorage = AuthStorage();
  final apiClient = ApiClient(
    baseUrl: 'http://10.0.2.2:8000',
    authStorage: authStorage,
  );

  final AuthServices authServices = AuthServices(
    apiClient: apiClient,
    authStorage: authStorage,
  );

  await authServices.login('testtest', 'testtest');

  print(await authStorage.getToken());

  final feedService = FeedService(apiClient: apiClient);

  final articles = await feedService.fetchArticles();
  print('Fetched ${articles.length} articles');
  print(
    'First article title: ${articles.isNotEmpty ? articles[0].title : 'No articles found'}',
  );
  ArticleDatabaseIO articleDb = ArticleDatabaseIO();
  for (var article in articles) {
    articleDb.setFavorite(article.articleId, true);
  }
  var favIds = await articleDb.getFavoriteArticleIds();
  print(favIds.toList());

  final syncService = SyncService(
    apiClient: apiClient,
    syncDatabase: SyncDatabaseIO(),
    articleDatabase: articleDb,
  );
  await syncService.flush();
  await syncService.pullStatus();
  favIds = await articleDb.getFavoriteArticleIds();
  print(favIds.toList());

  for (var i = 0; i < 5; i++) {
    await articleDb.setFavoriteWithSync(articles[i].articleId, true);
  }

  await syncService.flush();
  favIds = await articleDb.getFavoriteArticleIds();
  print(favIds.toList());

  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Placeholder(),
    ),
  );
}
