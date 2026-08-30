import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/data/api/client.dart';
import 'package:frontend_app/data/db/articledb.dart';
import 'package:frontend_app/data/db/syncdb.dart';
import 'package:frontend_app/data/service/sync_service.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'https://example.test', authStorage: null);

  ApiException? failure;
  String? requestedEndpoint;

  @override
  Future<Map<String, dynamic>> postJson(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    requestedEndpoint = endpoint;
    if (failure != null) throw failure!;
    return {'success': true};
  }

  @override
  Future<void> delete(String endpoint) async {
    requestedEndpoint = endpoint;
    if (failure != null) throw failure!;
  }
}

class _FakeArticleDatabase extends ArticleDatabaseIO {
  int? updatedArticleId;
  bool? updatedFavoriteState;

  @override
  Future<int> setFavorite(int id, bool isFavorite) async {
    updatedArticleId = id;
    updatedFavoriteState = isFavorite;
    return 1;
  }
}

class _FakeSyncDatabase extends SyncDatabaseIO {
  int? cleanedArticleId;

  @override
  Future<void> removeFavoriteActionsForArticle(int articleId) async {
    cleanedArticleId = articleId;
  }
}

void main() {
  late _FakeApiClient apiClient;
  late _FakeArticleDatabase articleDatabase;
  late _FakeSyncDatabase syncDatabase;
  late SyncService service;

  setUp(() {
    apiClient = _FakeApiClient();
    articleDatabase = _FakeArticleDatabase();
    syncDatabase = _FakeSyncDatabase();
    service = SyncService(
      apiClient: apiClient,
      syncDatabase: syncDatabase,
      articleDatabase: articleDatabase,
    );
  });

  test(
    'favorite is persisted only after a successful remote request',
    () async {
      await service.setFavoriteImmediately(42, true);

      expect(apiClient.requestedEndpoint, '/articles/42/favorite');
      expect(articleDatabase.updatedArticleId, 42);
      expect(articleDatabase.updatedFavoriteState, isTrue);
      expect(syncDatabase.cleanedArticleId, 42);
    },
  );

  test('remote failure leaves local favorite state untouched', () async {
    apiClient.failure = const ApiException('offline', 503);

    await expectLater(
      service.setFavoriteImmediately(42, false),
      throwsA(isA<ApiException>()),
    );

    expect(articleDatabase.updatedArticleId, isNull);
    expect(syncDatabase.cleanedArticleId, isNull);
  });

  test('idempotent backend response still reconciles local state', () async {
    apiClient.failure = const ApiException('already favorited', 409);

    await service.setFavoriteImmediately(42, true);

    expect(articleDatabase.updatedFavoriteState, isTrue);
    expect(syncDatabase.cleanedArticleId, 42);
  });
}
