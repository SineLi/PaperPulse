import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/auth/auth_services.dart';
import '../pages/setting_page.dart';

/// 包裹需要登录才能查看的页面。
/// 有 token 时正常渲染 [child]，无 token 时显示居中登录提示。
class LoginRequired extends StatefulWidget {
  final Widget child;
  final bool showScaffold;
  const LoginRequired({
    super.key,
    required this.child,
    this.showScaffold = true,
  });

  @override
  State<LoginRequired> createState() => _LoginRequiredState();
}

class _LoginRequiredState extends State<LoginRequired> {
  late Future<bool> _tokenFuture;

  @override
  void initState() {
    super.initState();
    _tokenFuture = context.read<AuthServices>().hasToken();
  }

  @override
  Widget build(BuildContext context) {
    // 第一层：检查 API 地址是否已配置
    final baseUrl = context.watch<SettingsController>().setting.baseURL.trim();
    if (baseUrl.isEmpty) {
      return widget.showScaffold
          ? Scaffold(body: _ApiNotConfiguredPrompt())
          : _ApiNotConfiguredPrompt();
    }

    // 第二层：检查是否已登录
    return FutureBuilder<bool>(
      future: _tokenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink(); // 极短暂，几乎不可见
        }
        if (snapshot.data == true) {
          return widget.child;
        }
        if (widget.showScaffold) {
          return Scaffold(body: _LoginPrompt());
        }
        return _LoginPrompt();
      },
    );
  }
}

class _ApiNotConfiguredPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            Text('未配置服务器地址', style: textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '请先在设置中配置 API 服务器地址，\n才能开始使用',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const NetworkSettingsPage(),
                ),
              ),
              icon: const Icon(Icons.settings_rounded),
              label: const Text('去配置'),
              style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            Text('尚未登录', style: textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '登录后即可查看文章、收藏和期刊',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/login'),
              icon: const Icon(Icons.login_rounded),
              label: const Text('去登录'),
              style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
            ),
          ],
        ),
      ),
    );
  }
}
