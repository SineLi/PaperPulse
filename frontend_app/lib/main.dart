import 'package:flutter/widgets.dart';
import 'data/auth/auth_services.dart';
import 'data/auth/auth_storage.dart';
import 'data/api/client.dart';
import 'data/service/feed_service.dart';

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
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Placeholder(),
    ),
  );
}
