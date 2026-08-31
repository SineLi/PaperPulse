import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/auth/auth_services.dart';
import '../data/service/post_auth_sync_service.dart';
import '../navigation/tab_scroll_registry.dart';
import '../settings/settings_controller.dart';

class AppShellPage extends StatefulWidget {
  final int currentIndex;
  final StatefulNavigationShell navigationShell;

  const AppShellPage({
    super.key,
    required this.currentIndex,
    required this.navigationShell,
  });

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  int _lastHandledSyncCompletion = 0;
  int get _currentIndex => widget.currentIndex;

  DateTime? _lastDestinationClickTime;
  int? _lastClickedIndex;

  // 缓存 hasToken() Future，避免每次 build 都重新创建导致重复读取和重建循环。
  Future<bool>? _hasTokenFuture;
  AuthServices? _authServices;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authServices = context.read<AuthServices>();
    // 仅在 AuthServices 实例变更时重新初始化 Future 并重新注册监听器。
    if (_authServices != authServices) {
      _authServices?.removeListener(_onAuthChanged);
      _authServices = authServices;
      authServices.addListener(_onAuthChanged);
      _hasTokenFuture = authServices.hasToken();
    }
  }

  /// 登录状态变化时刷新 token 检查 Future，确保 FutureBuilder 不使用过期结果。
  void _onAuthChanged() {
    final authServices = _authServices;
    if (authServices != null && mounted) {
      setState(() {
        _hasTokenFuture = authServices.hasToken();
      });
    }
  }

  @override
  void dispose() {
    _authServices?.removeListener(_onAuthChanged);
    super.dispose();
  }

  Future<void> _onDestinationClick(int index) async {
    final settings = context.read<SettingsController>().setting;
    final isSameTab = _currentIndex == index;

    if (settings.doubleTapToTop) {
      final now = DateTime.now();
      final isDoubleTap =
          isSameTab &&
          _lastClickedIndex == index &&
          _lastDestinationClickTime != null &&
          now.difference(_lastDestinationClickTime!) <
              Duration(milliseconds: settings.doubleTapSensitivity);

      if (isDoubleTap) {
        // The tab page owns the controller; the shell only triggers the action.
        await context.read<TabScrollRegistry>().handleDoubleTap(index);
        _lastDestinationClickTime = null;
        _lastClickedIndex = null;
        return;
      }

      _lastDestinationClickTime = now;
      _lastClickedIndex = index;
    }

    if (!isSameTab) {
      widget.navigationShell.goBranch(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final postAuthSyncService = context.watch<PostAuthSyncService>();
    _handleSyncCompletion(postAuthSyncService);

    return FutureBuilder<bool>(
      future: _hasTokenFuture,
      builder: (context, snapshot) {
        final hasToken = snapshot.data ?? false;

        final shellKey = ValueKey('AppShell-${hasToken ? "Auth" : "Guest"}');

        return Scaffold(
          key: shellKey,
          body: widget.navigationShell,
          bottomNavigationBar: NavigationBar(
            height: 64,
            selectedIndex: widget.navigationShell.currentIndex,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            onDestinationSelected: (index) async {
              await _onDestinationClick(index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.book_outlined),
                selectedIcon: Icon(Icons.book_rounded),
                label: '期刊',
              ),
              NavigationDestination(
                icon: Icon(Icons.favorite_outline_rounded),
                selectedIcon: Icon(Icons.favorite_rounded),
                label: '收藏',
              ),
              NavigationDestination(
                icon: Icon(Icons.article_outlined),
                selectedIcon: Icon(Icons.article_rounded),
                label: '首页',
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleSyncCompletion(PostAuthSyncService postAuthSyncService) {
    if (_lastHandledSyncCompletion == postAuthSyncService.completedSyncCount) {
      return;
    }
    _lastHandledSyncCompletion = postAuthSyncService.completedSyncCount;

    final newArticleCount = postAuthSyncService.lastNewArticleCount;
    if (newArticleCount <= 0) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已同步 $newArticleCount 条新数据')));
    });
  }
}
