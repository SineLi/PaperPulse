import '../api/client.dart';
import '../db/syncdb.dart';
import '../db/articledb.dart';
import '../models/article.dart';

class SyncService {
  final ApiClient _apiClient;
  final SyncDatabaseIO _syncDatabase;
  final ArticleDatabaseIO _articleDatabase;
  Future<void>? _pullStatusInFlight;

  SyncService({
    required ApiClient apiClient,
    required SyncDatabaseIO syncDatabase,
    required ArticleDatabaseIO? articleDatabase,
  }) : _apiClient = apiClient,
       _syncDatabase = syncDatabase,
       _articleDatabase = articleDatabase ?? ArticleDatabaseIO();

  /// 收藏动作直接提交后端；确认成功后才更新本地状态。
  Future<void> setFavoriteImmediately(int articleId, bool isFavorite) async {
    try {
      if (isFavorite) {
        await _apiClient.postJson('/articles/$articleId/favorite', {});
      } else {
        await _apiClient.delete('/articles/$articleId/favorite');
      }
    } on ApiException catch (error) {
      final alreadyInRequestedState =
          (isFavorite && error.statusCode == 409) ||
          (!isFavorite && error.statusCode == 404);
      if (!alreadyInRequestedState) rethrow;
    }

    await _articleDatabase.setFavorite(articleId, isFavorite);
    await _syncDatabase.removeFavoriteActionsForArticle(articleId);
  }

  Future<void> flush({int limit = 100}) async {
    final pendingActions = await _syncDatabase.getPendingSyncActions(
      limit: limit,
    );

    if (pendingActions.isEmpty) {
      return;
    }

    final List<int> processedIds = [];

    try {
      List<int> favIDs = pendingActions
          .where((action) => action['action'] == 'read')
          .map((action) => action['article_id'] as int)
          .toList();
      if (favIDs.isNotEmpty) {
        await _apiClient.postJson('/articles/read', {"items": favIDs});
      }

      processedIds.addAll(
        pendingActions
            .where((action) => action['action'] == 'read')
            .map((action) => action['id'] as int),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        for (var action in pendingActions) {
          if (action['action'] == 'read') {
            processedIds.add(action['id'] as int);
          }
        }
      } else {
        rethrow;
      }
    }

    for (var action in pendingActions.where(
      (action) =>
          action['action'] == 'favorite' || action['action'] == 'unfavorite',
    )) {
      final int id = action['id'] as int;
      final int articleId = action['article_id'] as int;
      final String actionType = action['action'] as String;

      try {
        if (actionType == 'favorite') {
          await _apiClient.postJson('/articles/$articleId/favorite', {});
        } else if (actionType == 'unfavorite') {
          await _apiClient.delete('/articles/$articleId/favorite');
        }
        processedIds.add(id);
      } on ApiException catch (e) {
        if (e.statusCode == 409 || e.statusCode == 404) {
          processedIds.add(id);
          continue;
        }
        rethrow;
      }
    }

    await _syncDatabase.removeSyncActions(processedIds);
  }

  Future<void> pullStatus() {
    final inFlight = _pullStatusInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _performPullStatus();
    _pullStatusInFlight = future;
    future.whenComplete(() {
      if (identical(_pullStatusInFlight, future)) {
        _pullStatusInFlight = null;
      }
    });
    return future;
  }

  Future<void> _performPullStatus() async {
    await flush();
    final data = await _apiClient.getJson('/articles/favorites');
    final raw = data['items'] as List;
    final Set<int> favoriteIds = raw.map((id) => id as int).toSet();
    final Set<int> localFavIds = await _articleDatabase.getFavoriteArticleIds();

    for (var toFav in favoriteIds.difference(localFavIds)) {
      if (await _articleDatabase.getArticle(toFav) == null) {
        try {
          final articleData = await _apiClient.getJson('/articles/$toFav');
          await _articleDatabase.addArticle(Article.fromJson(articleData));
        } on ApiException catch (e) {
          if (e.statusCode == 404) {
            continue;
          } else {
            rethrow;
          }
        }
      }
      await _articleDatabase.setFavorite(toFav, true);
    }

    for (var toUnfav in localFavIds.difference(favoriteIds)) {
      await _articleDatabase.setFavorite(toUnfav, false);
    }
  }
}
