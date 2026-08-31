import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/data/auth/auth_services.dart';
import 'package:frontend_app/navigation/tab_scroll_registry.dart';
import 'package:frontend_app/settings/settings_controller.dart';
import 'package:frontend_app/widgets/unified_list_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('search reset discards an older in-flight page load', (
    tester,
  ) async {
    final initialLoad = Completer<List<String>>();
    var userScrollStarts = 0;
    final harness = await _buildHarness(
      loadItems: (_, _) => initialLoad.future,
      searchItems: (query, _, _) async =>
          List.generate(30, (index) => '$query result $index'),
      onUserScrollStart: () => userScrollStarts += 1,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.widget);
    await tester.pump();

    await tester.tap(find.byTooltip('搜索'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.byType(SearchBar), 'new');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();

    expect(find.text('new result 0'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(userScrollStarts, 0);

    initialLoad.complete(['stale initial result']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('stale initial result'), findsNothing);
    expect(find.textContaining('new result'), findsWidgets);
  });

  testWidgets('filtered scrolling does not open the boundary write window', (
    tester,
  ) async {
    var userScrollStarts = 0;
    final harness = await _buildHarness(
      filterActive: true,
      loadItems: (_, _) async => List.generate(30, (index) => 'item $index'),
      onUserScrollStart: () => userScrollStarts += 1,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.widget);
    await tester.pump();
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();

    expect(userScrollStarts, 0);
  });
}

Future<_Harness> _buildHarness({
  required ItemLoader<String> loadItems,
  SearchLoader<String>? searchItems,
  bool filterActive = false,
  VoidCallback? onUserScrollStart,
}) async {
  SharedPreferences.setMockInitialValues({
    'settings.baseURL': 'https://example.test',
  });
  final settingsController = SettingsController(SettingStorage());
  await settingsController.load();
  final authServices = _FakeAuthServices();

  final widget = MultiProvider(
    providers: [
      Provider<TabScrollRegistry>(create: (_) => TabScrollRegistry()),
      ChangeNotifierProvider<AuthServices>.value(value: authServices),
      ChangeNotifierProvider<SettingsController>.value(
        value: settingsController,
      ),
    ],
    child: MaterialApp(
      home: UnifiedListPage<String>(
        title: 'Test list',
        loadItems: loadItems,
        searchItems: searchItems,
        filterActive: filterActive,
        onUserScrollStart: onUserScrollStart,
        itemBuilder:
            (
              context,
              item,
              index,
              allItems,
              isSearchActive,
              updateItem,
              updateItemById,
              removeItemById,
            ) => SizedBox(height: 80, child: Text(item)),
        skeletonBuilder: (_) => const SizedBox(height: 80),
      ),
    ),
  );

  return _Harness(
    widget: widget,
    dispose: () {
      authServices.dispose();
      settingsController.dispose();
    },
  );
}

class _Harness {
  final Widget widget;
  final VoidCallback dispose;

  const _Harness({required this.widget, required this.dispose});
}

class _FakeAuthServices extends ChangeNotifier implements AuthServices {
  @override
  bool get isLoggedIn => true;

  @override
  Future<bool> hasToken() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
