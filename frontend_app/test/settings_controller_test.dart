import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/settings/feed_card_style.dart';
import 'package:frontend_app/settings/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('feed card style defaults to masonry', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = SettingsController(SettingStorage());

    await controller.load();

    expect(controller.setting.feedCardStyle, FeedCardStyle.masonry);
  });

  test('feed card style persists across controller instances', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = SettingsController(SettingStorage());
    await controller.load();

    await controller.updateFeedCardStyle(FeedCardStyle.compact);

    final restoredController = SettingsController(SettingStorage());
    await restoredController.load();
    expect(restoredController.setting.feedCardStyle, FeedCardStyle.compact);
  });

  test('unknown stored feed card style falls back to masonry', () async {
    SharedPreferences.setMockInitialValues({
      'settings.feedCardStyle': 'removed-experiment',
    });
    final controller = SettingsController(SettingStorage());

    await controller.load();

    expect(controller.setting.feedCardStyle, FeedCardStyle.masonry);
  });
}
