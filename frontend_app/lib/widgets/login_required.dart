import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/auth/auth_services.dart';
import '../settings/settings_controller.dart';

/// 包裹需要登录才能查看的页面。
/// 已登录时显示 [child]；未登录时显示登录提示。
class LoginRequired extends StatelessWidget {
  final Widget child;
  final bool showScaffold;

  const LoginRequired({
    super.key,
    required this.child,
    this.showScaffold = true,
  });

  @override
  Widget build(BuildContext context) {
    final baseUrl = context.watch<SettingsController>().setting.baseURL.trim();
    if (baseUrl.isEmpty) {
      return showScaffold
          ? const Scaffold(body: _ApiNotConfiguredPrompt())
          : const _ApiNotConfiguredPrompt();
    }

    final authServices = context.watch<AuthServices>();

    // 登录成功后需要立刻放行，不能继续复用未登录时缓存下来的 Future 结果。
    if (authServices.isLoggedIn) {
      return child;
    }

    // 冷启动时 AuthServices 可能还没完成本地 token 状态恢复，这里兜底查一次本地凭证。
    return FutureBuilder<bool>(
      future: authServices.hasToken(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (snapshot.data == true) {
          return child;
        }
        if (showScaffold) {
          return const Scaffold(body: _LoginPrompt());
        }
        return const _LoginPrompt();
      },
    );
  }
}

class _ApiNotConfiguredPrompt extends StatelessWidget {
  const _ApiNotConfiguredPrompt();

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
              '请先在设置中配置 API 服务地址，才能开始使用。',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.push('/settings/network'),
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
  const _LoginPrompt();

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
              '登录后即可查看文章、收藏和期刊。',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.go('/login'),
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
