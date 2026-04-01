import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import "package:simple_icons/simple_icons.dart";
import 'package:url_launcher/url_launcher.dart';

import '../data/auth/auth_services.dart';
import '../data/db/articledb.dart';
import '../data/models/user.dart';
import '../settings/settings_controller.dart';
import '../widgets/policy_dialog.dart';

const _appName = 'PaperPulse';
const _appVersion = '0.0.3';
const _githubRepoUrl = 'https://github.com/SineLi/PaperPulse';

// ---------------------------------------------------------------------------
// Settings Home
// ---------------------------------------------------------------------------

class SettingPage extends StatelessWidget {
  const SettingPage({super.key});

  @override
  Widget build(BuildContext context) {
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
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const OperationSettingsPage(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.code_outlined),
                  title: Text('实验'),
                  subtitle: Text('正在测试的新功能'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ExperimentalPage(),
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('关于'),
                  subtitle: Text('$_appName v$_appVersion'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const AboutPage()),
                  ),
                ),
                SizedBox(height: 48),
              ]),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 账户子页
class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  bool _loading = true;
  User? _user;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final previousUser = _user;
    User? nextUser = previousUser;

    try {
      final authServices = context.read<AuthServices>();
      nextUser = await authServices.tryGetCurrentUser();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载账户信息失败: $e')));
    }

    if (!mounted) return;
    setState(() {
      _user = nextUser;
      _loading = false;
    });
  }

  Future<void> _refreshUser() async {
    setState(() => _loading = true);
    await _loadUser();
  }

  void _showChangePasswordPlaceholder() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('仍在开发')));
  }

  Future<void> _requestLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后将清理当前设备缓存，下次使用需要重新登录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('继续退出'),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;
    await _logout();
  }

  Future<void> _logout() async {
    final previousUser = _user;
    final authServices = context.read<AuthServices>();
    final articleDb = context.read<ArticleDatabaseIO>();
    setState(() => _loading = true);

    try {
      await authServices.logout();
      await articleDb.clearAll();
      if (!mounted) return;
      setState(() {
        _user = null;
        _loading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已退出登录，本地缓存已清理')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _user = previousUser;
        _loading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('退出失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
            const SliverAppBar.large(title: Text('账户')),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              SliverList(
                delegate: SliverChildListDelegate(
                  _user != null ? _buildLoggedIn() : _buildLoggedOut(),
                ),
              ),
        ],
      ),
    );
  }

  List<Widget> _buildLoggedIn() {
    final user = _user!;
    final colorScheme = Theme.of(context).colorScheme;

    return [
      const _SettingsSectionHeader(title: '账户信息'),
      _SettingsGroup(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('用户名'),
              subtitle: Text(user.username),
            ),
            const Divider(height: 1),
            _AccountInfoTile(
              icon: Icons.email_outlined,
              label: '邮箱',
              value: user.email,
            ),
          ],
        ),
      ),
      const _SettingsSectionHeader(title: '安全'),
      ListTile(
        leading: const Icon(Icons.password_rounded),
        title: const Text('修改密码'),
        subtitle: const Text('暂未开放'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: _showChangePasswordPlaceholder,
      ),
      const _SettingsSectionHeader(title: '会话'),
      ListTile(
        leading: const Icon(Icons.refresh_rounded),
        title: const Text('刷新账户状态'),
        onTap: _refreshUser,
      ),
      ListTile(
        leading: Icon(Icons.logout_rounded, color: colorScheme.error),
        title: Text('退出登录', style: TextStyle(color: colorScheme.error)),
        onTap: _requestLogout,
      ),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _buildLoggedOut() {
    return [
      const _SettingsSectionHeader(title: '账户'),
      const ListTile(
        leading: Icon(Icons.account_circle_outlined),
        title: Text('当前未登录'),
        subtitle: Text('登录后可同步订阅与收藏。'),
      ),
      ListTile(
        leading: const Icon(Icons.login_rounded),
        title: const Text('去登录'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/login'),
      ),
      const _SettingsSectionHeader(title: '安全'),
      ListTile(
        leading: const Icon(Icons.password_rounded),
        title: const Text('修改密码'),
        subtitle: const Text('登录后可用'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/login'),
      ),
      const _SettingsSectionHeader(title: '会话'),
      ListTile(
        leading: const Icon(Icons.refresh_rounded),
        title: const Text('刷新状态'),
        onTap: _refreshUser,
      ),
      const SizedBox(height: 24),
    ];
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
                  onSizeChanged: (v) => context
                      .read<SettingsController>()
                      .updateContentFontSize(v),
                ),
                _FontSizeRow(
                  label: '副标题',
                  value: settings.headerFontSize,
                  min: 16,
                  max: 32,
                  isBold: settings.headerBold,
                  showBoldToggle: true,
                  onSizeChanged: (v) => context
                      .read<SettingsController>()
                      .updateHeaderFontSize(v),
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
                SizedBox(height: 64),
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
    if (!mounted) return;
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
                          hintText: '',
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
                  onChanged: (v) => context
                      .read<SettingsController>()
                      .updateWifiOnlyImages(v),
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
class OperationSettingsPage extends StatefulWidget {
  const OperationSettingsPage({super.key});

  @override
  State<OperationSettingsPage> createState() => _OperationSettingsPageState();
}

class _OperationSettingsPageState extends State<OperationSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().setting;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
            const SliverAppBar.large(title: Text('操作')),
            SliverList(
              delegate: SliverChildListDelegate([
                const _SettingsSectionHeader(title: '手势'),
                SwitchListTile(
                  secondary: const Icon(Icons.swipe_up_rounded),
                  title: const Text('上滑切换文章'),
                  subtitle: const Text('在底端继续向上滑动切换到下一篇文章'),
                  value: settings.swipeToChangeArticleUp,
                  onChanged: (v) => context
                      .read<SettingsController>()
                      .updateSwipeToChangeArticleUp(v),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.swipe_down_rounded),
                  title: const Text('下滑切换文章'),
                  subtitle: const Text('在顶端继续向下滑动切换到上一篇文章'),
                  value: settings.swipeToChangeArticleDown,
                  onChanged: (v) => context
                      .read<SettingsController>()
                      .updateSwipeToChangeArticleDown(v),
                ),
                SizedBox(height: 12),
                _FontSizeRow(
                  label: '滑动切换灵敏度',
                  value: settings.swipeSensitivity,
                  min: 50,
                  max: 200,
                  onSizeChanged: (v) => context
                      .read<SettingsController>()
                      .updateSwipeSensitivity(v),
                ),
                const _SettingsSectionHeader(title: '导航'),
                SwitchListTile(
                  secondary: const Icon(Icons.vertical_align_top_rounded),
                  title: const Text('双击导航栏回到顶部'),
                  subtitle: const Text('在主页双击底部导航栏的当前标签页，可以快速滚动到页面顶部'),
                  value: settings.doubleTapToTop,
                  onChanged: (v) => context
                      .read<SettingsController>()
                      .updateDoubleTapToTop(v),
                ),
                SizedBox(height: 12),
                _FontSizeRow(
                  label: '双击灵敏度',
                  value: settings.doubleTapSensitivity,
                  min: 100,
                  max: 1000,
                  unit: 'ms',
                  onSizeChanged: (v) => context
                      .read<SettingsController>()
                      .updateDoubleTapSensitivity(v),
                ),
                SizedBox(height: 20),
              ]),
            ),
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
            const SliverAppBar.large(title: Text('关于')),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: SvgPicture.asset('assets/logo.svg', width: 64),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _appName,
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.secondaryContainer,
                        ),
                      ),
                      child: Text(
                        'Version $_appVersion',
                        style: textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const Spacer(flex: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () async {
                            launchUrl(
                              Uri.parse(_githubRepoUrl),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          onLongPress: () async {
                            await Clipboard.setData(
                              const ClipboardData(text: _githubRepoUrl),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('GitHub 链接已复制')),
                            );
                          },
                          icon: const Icon(SimpleIcons.github, size: 20),
                          label: const Text('GitHub 仓库'),
                        ),
                        const SizedBox(width: 16),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => LicensePage(
                                  applicationName: _appName,
                                  applicationVersion: _appVersion,
                                  applicationIcon: Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: SvgPicture.asset(
                                      'assets/logo.svg',
                                      width: 64,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.description_outlined,
                            size: 20,
                          ),
                          label: const Text('开源许可'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () {
                            showPolicyDialog(
                              context,
                              title: '用户协议',
                              content: userAgreementContent,
                            );
                          },
                          icon: const Icon(
                            Icons.description_outlined,
                            size: 20,
                          ),
                          label: const Text('用户协议'),
                        ),
                        const SizedBox(width: 16),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            showPolicyDialog(
                              context,
                              title: '隐私政策',
                              content: privacyPolicyContent,
                            );
                          },
                          icon: const Icon(
                            Icons.privacy_tip_outlined,
                            size: 20,
                          ),
                          label: const Text('隐私政策'),
                        ),
                      ],
                    ),
                    const Spacer(flex: 3),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 关于/账户辅助组件

class _SettingsGroup extends StatelessWidget {
  final Widget child;

  const _SettingsGroup({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: child,
      ),
    );
  }
}

class _AccountInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _AccountInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
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
  final String unit;
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
    this.unit = 'px',
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
                  '$value $unit',
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

// 实验
class ExperimentalPage extends StatelessWidget {
  const ExperimentalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
            const SliverAppBar.large(title: Text('实验功能')),
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('暂无实验功能，敬请期待！')),
            ),
        ],
      ),
    );
  }
}
