import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import './article_detail_page.dart';

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

  Future<AppSetting> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSetting(
      themeMode: prefs.getInt(_keyThemeMode) ?? 2,
      amoled: prefs.getBool(_keyAmoled) ?? false,
      baseURL: prefs.getString(_keyBaseURL) ?? 'https://api.fooood.life',
      contentFontSize: prefs.getInt(_keyContentFontSize) ?? 16,
      headerFontSize: prefs.getInt(_keyHeaderFontSize) ?? 24,
      titleFontSize: prefs.getInt(_keyTitleFontSize) ?? 28,
      headerBold: prefs.getBool(_keyHeaderBold) ?? true,
      titleBold: prefs.getBool(_keyTitleBold) ?? true,
      wifiOnlyImages: prefs.getBool(_keyWifiOnlyImages) ?? false,
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
  }
}

class SettingsController extends ChangeNotifier {
  SettingsController(this._storage);

  final SettingStorage _storage;
  AppSetting _setting = AppSetting(
    themeMode: 2,
    baseURL: 'https://api.fooood.life',
    amoled: false,
    contentFontSize: 16,
    headerFontSize: 24,
    titleFontSize: 28,
    headerBold: true,
    titleBold: true,
    wifiOnlyImages: false,
  );

  AppSetting get setting => _setting;
  ThemeMode get themeMode => _setting.themeModeValue; // 给 MaterialApp 用

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
}

// ---------------------------------------------------------------------------
// 设置主页 — 入口列表
// ---------------------------------------------------------------------------

class SettingPage extends StatelessWidget {
  const SettingPage({super.key});

  String _themeModeLabel(int mode) {
    switch (mode) {
      case 0:
        return '浅色';
      case 1:
        return '深色';
      default:
        return '跟随系统';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().setting;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('设置')),
          SliverList(
            delegate: SliverChildListDelegate([
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('账户'),
                subtitle: Text('账户信息，登录状态'),
                // trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AccountSettingsPage(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('外观'),
                subtitle: Text('颜色，字体'),
                // trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ThemeSettingsPage(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.public_rounded),
                title: const Text('网络'),
                subtitle: Text('后端接口，图片下载'),
                // trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NetworkSettingsPage(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.gesture_outlined),
                title: const Text('操作'),
                subtitle: Text('手势，动画'),
                // trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OperationSettingsPage(),
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('关于'),
                subtitle: Text('PaperPulse v1.0'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutPage()),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 账户子页

class AccountSettingsPage extends StatelessWidget {
  const AccountSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('账户')),
          const SliverFillRemaining(child: Center(child: Text('敬请期待'))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 外观子页
// ---------------------------------------------------------------------------

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().setting;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('外观')),
          SliverList(
            delegate: SliverChildListDelegate([
              const _SettingsSectionHeader(title: '颜色'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment<int>(value: 0, label: Text('浅色')),
                    ButtonSegment<int>(value: 1, label: Text('深色')),
                    ButtonSegment<int>(value: 2, label: Text('跟随系统')),
                  ],
                  selected: <int>{settings.themeMode},
                  onSelectionChanged: (selection) {
                    context.read<SettingsController>().updateThemeMode(
                      selection.first,
                    );
                  },
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.contrast),
                title: const Text('AMOLED 深黑'),
                subtitle: const Text('仅在深色主题下生效'),
                value: settings.amoled,
                onChanged: (value) {
                  context.read<SettingsController>().updateAmoled(value);
                },
              ),
              const _SettingsSectionHeader(title: '字体'),

              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '三体·黑暗森林',
                            style: TextStyle(
                              fontSize: settings.titleFontSize.toDouble(),
                              fontWeight: settings.titleBold
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '序章',
                            style: TextStyle(
                              fontSize: settings.headerFontSize.toDouble(),
                              fontWeight: settings.headerBold
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            """褐蚁已经忘记这里曾是它的家园。这段时光对于暮色中的大地和刚刚出现的星星来说短得可以忽略不计，但对于它来说却是漫长的。
在那个已被忘却的日子里，它的世界颠覆了。泥土飞走，出现了一条又深又宽的峡谷，然后泥土又轰隆隆地飞回来，峡谷消失了，在原来峡谷的尽头出现了一座黑色的孤峰。其实，在这片广阔的疆域上，这种事常常发生，泥土飞走又飞回，峡谷出现又消失，然后是孤峰降临，好像是给每次灾变打上一个醒目的标记。褐蚁和几百个同族带着幸存的蚁后向太阳落下的方向走了一段路，建立了新的帝国。""",
                            style: TextStyle(
                              fontSize: settings.contentFontSize.toDouble(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12),
              _FontSizeRow(
                label: '正文',
                value: settings.contentFontSize,
                min: 12,
                max: 24,
                onSizeChanged: (v) =>
                    context.read<SettingsController>().updateContentFontSize(v),
              ),
              _FontSizeRow(
                label: '副标题',
                value: settings.headerFontSize,
                min: 16,
                max: 32,
                isBold: settings.headerBold,
                showBoldToggle: true,
                onSizeChanged: (v) =>
                    context.read<SettingsController>().updateHeaderFontSize(v),
                onBoldChanged: (b) =>
                    context.read<SettingsController>().updateHeaderBold(b),
              ),
              _FontSizeRow(
                label: '标题',
                value: settings.titleFontSize,
                min: 20,
                max: 40,
                isBold: settings.titleBold,
                showBoldToggle: true,
                onSizeChanged: (v) =>
                    context.read<SettingsController>().updateTitleFontSize(v),
                onBoldChanged: (b) =>
                    context.read<SettingsController>().updateTitleBold(b),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 网络子页
// ---------------------------------------------------------------------------

class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key});

  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  late final TextEditingController _baseUrlController;

  @override
  void initState() {
    super.initState();
    final baseUrl = context.read<SettingsController>().setting.baseURL;
    _baseUrlController = TextEditingController(text: baseUrl);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveBaseUrl() async {
    final controller = context.read<SettingsController>();
    final input = _baseUrlController.text.trim();
    final uri = Uri.tryParse(input);

    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效的 http/https 地址')));
      return;
    }

    await controller.updateBaseURL(input);
    if (!context.mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('接口地址已保存')));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().setting;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('网络')),
          SliverList(
            delegate: SliverChildListDelegate([
              const _SettingsSectionHeader(title: 'API 接口'),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _baseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'API Base URL',
                        hintText: 'https://api.fooood.life',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _saveBaseUrl,
                        child: const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ),
              const _SettingsSectionHeader(title: '图片下载'),
              SwitchListTile(
                secondary: const Icon(Icons.wifi_rounded),
                title: const Text('仅在 Wi-Fi 下下载图片'),
                subtitle: const Text('移动网络下将不加载封面与图形摘要'),
                value: settings.wifiOnlyImages,
                onChanged: (v) =>
                    context.read<SettingsController>().updateWifiOnlyImages(v),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 操作子页

class OperationSettingsPage extends StatelessWidget {
  const OperationSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('操作')),
          const SliverFillRemaining(child: Center(child: Text('敬请期待'))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 关于页

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('关于')),
          const SliverFillRemaining(
            child: Center(
              child: Text(
                'PaperPulse v1.0\nPowered by Flutter',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 辅助组件

class _SettingsSectionHeader extends StatelessWidget {
  final String title;
  const _SettingsSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ── 字体大小调节行 ──
class _FontSizeRow extends StatelessWidget {
  final String label;
  final int value;
  final double min;
  final double max;
  final bool showBoldToggle;
  final bool isBold;
  final ValueChanged<int> onSizeChanged;
  final ValueChanged<bool>? onBoldChanged;

  const _FontSizeRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onSizeChanged,
    this.showBoldToggle = false,
    this.isBold = false,
    this.onBoldChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final clampedValue = value.toDouble().clamp(min, max);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: textTheme.bodyLarge),
              const SizedBox(width: 10),
              // 字号徽章
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$value px',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              if (showBoldToggle)
                FilterChip(
                  avatar: const Icon(Icons.format_bold_rounded, size: 15),
                  label: const Text('加粗'),
                  selected: isBold,
                  onSelected: onBoldChanged,
                  visualDensity: VisualDensity.compact,
                  labelStyle: textTheme.labelSmall,
                  side: BorderSide(
                    color: isBold
                        ? colorScheme.primary
                        : colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
            ),
            child: Slider(
              value: clampedValue,
              min: min,
              max: max,
              onChanged: (v) => onSizeChanged(v.round()),
            ),
          ),
        ],
      ),
    );
  }
}
