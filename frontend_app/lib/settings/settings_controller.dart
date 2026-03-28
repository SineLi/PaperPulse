import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSetting {
  final int themeMode; // '0light', '1dark', '2system'
  final bool amoled;
  final String baseURL;

  final int contentFontSize;
  final int headerFontSize;
  final int titleFontSize;
  final bool headerBold;
  final bool titleBold;
  final bool wifiOnlyImages;
  final bool swipeToChangeArticleUp;
  final bool swipeToChangeArticleDown;
  final int swipeSensitivity; // 50-200 px
  final bool enablePredictiveBack;
  final bool doubleTapToTop;
  final int doubleTapSensitivity; // 100-1000 ms

  AppSetting({
    required this.themeMode,
    required this.baseURL,
    required this.amoled,
    this.contentFontSize = 16,
    this.headerFontSize = 24,
    this.titleFontSize = 28,
    this.headerBold = true,
    this.titleBold = true,
    this.wifiOnlyImages = false,
    this.swipeToChangeArticleUp = true,
    this.swipeToChangeArticleDown = true,
    this.swipeSensitivity = 120,
    this.enablePredictiveBack = true,
    this.doubleTapToTop = true,
    this.doubleTapSensitivity = 300,
  });

  AppSetting copyWith({
    int? themeMode,
    bool? amoled,
    String? baseURL,
    int? contentFontSize,
    int? headerFontSize,
    int? titleFontSize,
    bool? headerBold,
    bool? titleBold,
    bool? wifiOnlyImages,
    bool? swipeToChangeArticleUp,
    bool? swipeToChangeArticleDown,
    int? swipeSensitivity,
    bool? enablePredictiveBack,
    bool? doubleTapToTop,
    int? doubleTapSensitivity,
  }) {
    return AppSetting(
      themeMode: themeMode ?? this.themeMode,
      amoled: amoled ?? this.amoled,
      baseURL: baseURL ?? this.baseURL,
      contentFontSize: contentFontSize ?? this.contentFontSize,
      headerFontSize: headerFontSize ?? this.headerFontSize,
      titleFontSize: titleFontSize ?? this.titleFontSize,
      headerBold: headerBold ?? this.headerBold,
      titleBold: titleBold ?? this.titleBold,
      wifiOnlyImages: wifiOnlyImages ?? this.wifiOnlyImages,
      swipeToChangeArticleUp:
          swipeToChangeArticleUp ?? this.swipeToChangeArticleUp,
      swipeToChangeArticleDown:
          swipeToChangeArticleDown ?? this.swipeToChangeArticleDown,
      swipeSensitivity: swipeSensitivity ?? this.swipeSensitivity,
      enablePredictiveBack: enablePredictiveBack ?? this.enablePredictiveBack,
      doubleTapToTop: doubleTapToTop ?? this.doubleTapToTop,
      doubleTapSensitivity: doubleTapSensitivity ?? this.doubleTapSensitivity,
    );
  }

  ThemeMode get themeModeValue {
    switch (themeMode) {
      case 0:
        return ThemeMode.light;
      case 1:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}

class SettingStorage {
  static const String _keyThemeMode = 'settings.themeMode';
  static const String _keyAmoled = 'settings.amoled';
  static const String _keyBaseURL = 'settings.baseURL';
  static const String _keyContentFontSize = 'settings.contentFontSize';
  static const String _keyHeaderFontSize = 'settings.headerFontSize';
  static const String _keyTitleFontSize = 'settings.titleFontSize';
  static const String _keyHeaderBold = 'settings.headerBold';
  static const String _keyTitleBold = 'settings.titleBold';
  static const String _keyWifiOnlyImages = 'settings.wifiOnlyImages';
  static const String _keySwipeToChangeArticleUp =
      'settings.swipeToChangeArticleUp';
  static const String _keySwipeToChangeArticleDown =
      'settings.swipeToChangeArticleDown';
  static const String _keySwipeSensitivity = 'settings.swipeSensitivity';
  static const String _keyEnablePredictiveBack =
      'settings.enablePredictiveBack';
  static const String _keyDoubleTapToTop = 'settings.doubleTapToTop';
  static const String _keyDoubleTapSensitivity =
      'settings.doubleTapSensitivity';

  Future<AppSetting> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSetting(
      themeMode: prefs.getInt(_keyThemeMode) ?? 2,
      amoled: prefs.getBool(_keyAmoled) ?? false,
      baseURL: prefs.getString(_keyBaseURL) ?? '',
      contentFontSize: prefs.getInt(_keyContentFontSize) ?? 16,
      headerFontSize: prefs.getInt(_keyHeaderFontSize) ?? 24,
      titleFontSize: prefs.getInt(_keyTitleFontSize) ?? 28,
      headerBold: prefs.getBool(_keyHeaderBold) ?? true,
      titleBold: prefs.getBool(_keyTitleBold) ?? true,
      wifiOnlyImages: prefs.getBool(_keyWifiOnlyImages) ?? false,
      swipeToChangeArticleUp: prefs.getBool(_keySwipeToChangeArticleUp) ?? true,
      swipeToChangeArticleDown:
          prefs.getBool(_keySwipeToChangeArticleDown) ?? true,
      swipeSensitivity: prefs.getInt(_keySwipeSensitivity) ?? 140,
      enablePredictiveBack: prefs.getBool(_keyEnablePredictiveBack) ?? true,
      doubleTapToTop: prefs.getBool(_keyDoubleTapToTop) ?? true,
      doubleTapSensitivity: prefs.getInt(_keyDoubleTapSensitivity) ?? 300,
    );
  }

  Future<void> save(AppSetting setting) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyThemeMode, setting.themeMode);
    await prefs.setBool(_keyAmoled, setting.amoled);
    await prefs.setString(_keyBaseURL, setting.baseURL);
    await prefs.setInt(_keyContentFontSize, setting.contentFontSize);
    await prefs.setInt(_keyHeaderFontSize, setting.headerFontSize);
    await prefs.setInt(_keyTitleFontSize, setting.titleFontSize);
    await prefs.setBool(_keyHeaderBold, setting.headerBold);
    await prefs.setBool(_keyTitleBold, setting.titleBold);
    await prefs.setBool(_keyWifiOnlyImages, setting.wifiOnlyImages);
    await prefs.setBool(
      _keySwipeToChangeArticleUp,
      setting.swipeToChangeArticleUp,
    );
    await prefs.setBool(
      _keySwipeToChangeArticleDown,
      setting.swipeToChangeArticleDown,
    );
    await prefs.setInt(_keySwipeSensitivity, setting.swipeSensitivity);
    await prefs.setBool(_keyEnablePredictiveBack, setting.enablePredictiveBack);
    await prefs.setBool(_keyDoubleTapToTop, setting.doubleTapToTop);
    await prefs.setInt(_keyDoubleTapSensitivity, setting.doubleTapSensitivity);
  }
}

class SettingsController extends ChangeNotifier {
  SettingsController(this._storage);

  final SettingStorage _storage;
  AppSetting _setting = AppSetting(
    themeMode: 2,
    baseURL: '',
    amoled: false,
    contentFontSize: 16,
    headerFontSize: 24,
    titleFontSize: 28,
    headerBold: true,
    titleBold: true,
    wifiOnlyImages: false,
    doubleTapSensitivity: 300,
  );

  AppSetting get setting => _setting;
  ThemeMode get themeMode => _setting.themeModeValue;

  Future<void> load() async {
    _setting = await _storage.load();
    notifyListeners();
  }

  Future<void> updateThemeMode(int mode) async {
    _setting = _setting.copyWith(themeMode: mode);
    await _storage.save(_setting);
    notifyListeners();
  }

  Future<void> updateAmoled(bool enabled) async {
    _setting = _setting.copyWith(amoled: enabled);
    await _storage.save(_setting);
    notifyListeners();
  }

  Future<void> updateBaseURL(String baseURL) async {
    _setting = _setting.copyWith(baseURL: baseURL);
    await _storage.save(_setting);
    notifyListeners();
  }

  Future<void> updateContentFontSize(int size) async {
    _setting = _setting.copyWith(contentFontSize: size);
    await _storage.save(_setting);
    notifyListeners();
  }

  Future<void> updateHeaderFontSize(int size) async {
    _setting = _setting.copyWith(headerFontSize: size);
    await _storage.save(_setting);
    notifyListeners();
  }

  Future<void> updateTitleFontSize(int size) async {
    _setting = _setting.copyWith(titleFontSize: size);
    await _storage.save(_setting);
    notifyListeners();
  }

  Future<void> updateHeaderBold(bool bold) async {
    _setting = _setting.copyWith(headerBold: bold);
    await _storage.save(_setting);
    notifyListeners();
  }

  Future<void> updateTitleBold(bool bold) async {
    _setting = _setting.copyWith(titleBold: bold);
    await _storage.save(_setting);
    notifyListeners();
  }

  Future<void> updateWifiOnlyImages(bool enabled) async {
    _setting = _setting.copyWith(wifiOnlyImages: enabled);
    await _storage.save(_setting);
    notifyListeners();
  }

  Future<void> updateSwipeToChangeArticleUp(bool enabled) async {
    _setting = _setting.copyWith(swipeToChangeArticleUp: enabled);
    await _storage.save(_setting);
    notifyListeners();
  }

  Future<void> updateSwipeToChangeArticleDown(bool enabled) async {
    _setting = _setting.copyWith(swipeToChangeArticleDown: enabled);
    await _storage.save(_setting);
    notifyListeners();
  }

  Future<void> updateSwipeSensitivity(int sensitivity) async {
    _setting = _setting.copyWith(swipeSensitivity: sensitivity);
    await _storage.save(_setting);
    notifyListeners();
  }

  Future<void> updateEnablePredictiveBack(bool enabled) async {
    _setting = _setting.copyWith(enablePredictiveBack: enabled);
    await _storage.save(_setting);
    notifyListeners();
  }

  Future<void> updateDoubleTapToTop(bool enabled) async {
    _setting = _setting.copyWith(doubleTapToTop: enabled);
    await _storage.save(_setting);
    notifyListeners();
  }

  Future<void> updateDoubleTapSensitivity(int sensitivity) async {
    _setting = _setting.copyWith(doubleTapSensitivity: sensitivity);
    await _storage.save(_setting);
    notifyListeners();
  }
}

// ── 可预测返回作用域 ──
/// 根据 [SettingsController.setting.enablePredictiveBack] 的值,
/// 决定是否允许 Android 系统级可预测返回手势动画。
/// 当关闭时, 用 [PopScope] 阻止系统预测预览, 但正常返回仍可用。
class PredictiveBackScope extends StatelessWidget {
  final Widget child;
  const PredictiveBackScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final enabled = context
        .watch<SettingsController>()
        .setting
        .enablePredictiveBack;
    if (enabled) return child;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(result);
      },
      child: child,
    );
  }
}
