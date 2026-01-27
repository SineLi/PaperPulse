import '../api/client.dart';
import '../db/syncdb.dart';

class SyncService {
  final ApiClient _apiClient;
  final SyncDatabaseIO _syncDatabase;

  SyncService({
    required ApiClient apiClient,
    required SyncDatabaseIO syncDatabase,
  }) : _apiClient = apiClient,
       _syncDatabase = syncDatabase;

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
        throw Exception('Failed to sync read actions: $e');
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
          await _apiClient.deleteJson('/articles/$articleId/favorite');
        }
        processedIds.add(id);
      } on ApiException catch (e) {
        if (e.statusCode == 409 || e.statusCode == 404) {
          processedIds.add(id);
          continue;
        }
        throw Exception('Failed to sync favorite/unfavorite actions: $e');
      }
    }

    await _syncDatabase.removeSyncActions(processedIds);
  }
}
