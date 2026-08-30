import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/data/api/client.dart';
import 'package:frontend_app/data/db/articledb.dart';
import 'package:frontend_app/data/db/syncdb.dart';
import 'package:frontend_app/data/service/sync_service.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'https://example.test', authStorage: null);

  ApiException? failure;
  String? requestedEndpoint;
  final List<String> requestLog = [];
  Completer<Map<String, dynamic>>? favoritesResponse;

  @override
  Future<Map<String, dynamic>> postJson(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    requestedEndpoint = endpoint;
    requestLog.add('POST $endpoint');
    if (failure != null) throw failure!;
    return {'success': true};
  }

  @override
  Future<void> delete(String endpoint) async {
    requestedEndpoint = endpoint;
    requestLog.add('DELETE $endpoint');
    if (failure != null) throw failure!;
  }

  @override
  Future<Map<String, dynamic>> getJson(String endpoint) {
    requestedEndpoint = endpoint;
    requestLog.add('GET $endpoint');
    if (failure != null) throw failure!;
    if (endpoint == '/articles/favorites') {
      return favoritesResponse?.future ?? Future.value({'items': <int>[]});
    }
    return Future.value(<String, dynamic>{});
  }
}

class _FakeArticleDatabase extends ArticleDatabaseIO {
  int? updatedArticleId;
  bool? updatedFavoriteState;
  final Set<int> favoriteArticleIds = {};

  @override
  Future<int> setFavorite(int id, bool isFavorite) async {
    updatedArticleId = id;
    updatedFavoriteState = isFavorite;
    if (isFavorite) {
      favoriteArticleIds.add(id);
    } else {
      favoriteArticleIds.remove(id);
    }
    return 1;
  }

  @override
  Future<Set<int>> getFavoriteArticleIds() async =>
      Set<int>.of(favoriteArticleIds);
}

class _FakeSyncDatabase extends SyncDatabaseIO {
  int? cleanedArticleId;
  int pendingActionReads = 0;
  bool hasLegacyUnfavoriteAction = false;

  @override
  Future<void> removeFavoriteActionsForArticle(int articleId) async {
    cleanedArticleId = articleId;
    hasLegacyUnfavoriteAction = false;
  }

  @override
  Future<List<Map<String, Object?>>> getPendingSyncActions({
    int limit = 100,
    int offset = 0,
  }) async {
    pendingActionReads += 1;
    if (!hasLegacyUnfavoriteAction) return const [];
    return const [
      {'id': 1, 'article_id': 42, 'action': 'unfavorite'},
    ];
  }

  @override
  Future<void> removeSyncActions(List<int> ids) async {
    if (ids.contains(1)) hasLegacyUnfavoriteAction = false;
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

  test(
    'favorite waits for an in-flight status pull and wins afterward',
    () async {
      final favoritesResponse = Completer<Map<String, dynamic>>();
      apiClient.favoritesResponse = favoritesResponse;

      final pull = service.pullStatus();
      await Future<void>.delayed(Duration.zero);
      expect(apiClient.requestLog, ['GET /articles/favorites']);

      final favorite = service.setFavoriteImmediately(42, true);
      await Future<void>.delayed(Duration.zero);
      expect(apiClient.requestLog, ['GET /articles/favorites']);

      favoritesResponse.complete({'items': <int>[]});
      await Future.wait([pull, favorite]);

      expect(apiClient.requestLog, [
        'GET /articles/favorites',
        'POST /articles/42/favorite',
      ]);
      expect(articleDatabase.favoriteArticleIds, {42});
    },
  );

  test(
    'flush waits until an immediate favorite clears legacy actions',
    () async {
      syncDatabase.hasLegacyUnfavoriteAction = true;
      final favorite = service.setFavoriteImmediately(42, true);
      final flush = service.flush();

      await Future.wait([favorite, flush]);

      expect(syncDatabase.cleanedArticleId, 42);
      expect(syncDatabase.pendingActionReads, 1);
      expect(apiClient.requestLog, ['POST /articles/42/favorite']);
    },
  );
}
