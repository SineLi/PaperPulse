import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/pages/setting_page.dart';
import 'package:frontend_app/settings/feed_card_style.dart';
import 'package:frontend_app/settings/settings_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('experimental page selects and persists a card style', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = SettingsController(SettingStorage());
    await controller.load();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsController>.value(
        value: controller,
        child: const MaterialApp(home: ExperimentalPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('文章卡片'), findsOneWidget);
    expect(find.textContaining('首页与收藏页'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('feed-card-style-compact')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('feed-card-style-compact')));
    await tester.pumpAndSettle();

    expect(controller.setting.feedCardStyle, FeedCardStyle.compact);
    final selectedOption = find.byKey(
      const ValueKey('feed-card-style-compact'),
    );
    final selectedMaterial = tester.widget<Material>(selectedOption);
    final selectedInkWell = tester.widget<InkWell>(
      find.descendant(of: selectedOption, matching: find.byType(InkWell)),
    );
    expect(selectedInkWell.customBorder, selectedMaterial.shape);
    expect((selectedMaterial.shape! as RoundedRectangleBorder).side.width, 2);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('settings.feedCardStyle'), 'compact');

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('feed-card-style-masonry')),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('feed-card-style-masonry')),
      findsOneWidget,
    );
  });
}
