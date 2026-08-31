import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/data/auth/auth_services.dart';
import 'package:frontend_app/navigation/tab_scroll_registry.dart';
import 'package:frontend_app/settings/settings_controller.dart';
import 'package:frontend_app/widgets/journal_list_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'reloads filter facets after the catalog refresh signal changes',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings.baseURL': 'https://example.test',
      });
      final settingsController = SettingsController(SettingStorage());
      await settingsController.load();
      final authServices = _FakeAuthServices();
      addTearDown(settingsController.dispose);
      addTearDown(authServices.dispose);

      var publisherLoads = 0;
      var categoryLoads = 0;
      Completer<List<String>>? blockedPublisherLoad;
      Completer<List<String>>? blockedCategoryLoad;

      Widget buildPage(int signal) {
        return MultiProvider(
          providers: [
            Provider<TabScrollRegistry>(create: (_) => TabScrollRegistry()),
            ChangeNotifierProvider<AuthServices>.value(value: authServices),
            ChangeNotifierProvider<SettingsController>.value(
              value: settingsController,
            ),
          ],
          child: MaterialApp(
            home: JournalListPage(
              key: const ValueKey('journals'),
              title: 'Journals',
              loadJournals: (_, _, _) async => [],
              isFollowed: (_) => false,
              loadFilterPublishers: () async {
                publisherLoads += 1;
                final blocked = blockedPublisherLoad;
                if (blocked != null) {
                  blockedPublisherLoad = null;
                  return blocked.future;
                }
                return ['Publisher $publisherLoads'];
              },
              loadFilterCasCategories: () async {
                categoryLoads += 1;
                final blocked = blockedCategoryLoad;
                if (blocked != null) {
                  blockedCategoryLoad = null;
                  return blocked.future;
                }
                return ['Category $categoryLoads'];
              },
              externalRefreshSignal: signal,
            ),
          ),
        );
      }

      await tester.pumpWidget(buildPage(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('筛选'));
      await tester.pumpAndSettle();
      expect(publisherLoads, 1);
      expect(categoryLoads, 1);

      Navigator.of(tester.element(find.byType(JournalListPage))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('筛选'));
      await tester.pumpAndSettle();
      expect(publisherLoads, 1);
      expect(categoryLoads, 1);

      Navigator.of(tester.element(find.byType(JournalListPage))).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(buildPage(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('筛选'));
      await tester.pumpAndSettle();

      expect(publisherLoads, 2);
      expect(categoryLoads, 2);

      Navigator.of(tester.element(find.byType(JournalListPage))).pop();
      await tester.pumpAndSettle();
      final stalePublisherLoad = Completer<List<String>>();
      final staleCategoryLoad = Completer<List<String>>();
      blockedPublisherLoad = stalePublisherLoad;
      blockedCategoryLoad = staleCategoryLoad;
      await tester.pumpWidget(buildPage(2));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('筛选'));
      await tester.pump();
      expect(publisherLoads, 3);
      expect(categoryLoads, 3);

      await tester.pumpWidget(buildPage(3));
      await tester.pump();
      stalePublisherLoad.complete(['Stale publisher']);
      staleCategoryLoad.complete(['Stale category']);
      await tester.pumpAndSettle();

      expect(publisherLoads, 4);
      expect(categoryLoads, 4);
    },
  );
}

class _FakeAuthServices extends ChangeNotifier implements AuthServices {
  @override
  bool get isLoggedIn => true;

  @override
  Future<bool> hasToken() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
