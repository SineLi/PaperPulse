import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/auth/auth_services.dart';
import '../data/service/post_auth_sync_service.dart';
import '../settings/settings_controller.dart';
import 'fav_page.dart';
import 'feed_page.dart';
import 'journal_page.dart';

class AppShellPage extends StatefulWidget {
  const AppShellPage({super.key});

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  int _currentIndex = 2; // Default to Feed
  int _lastHandledSyncCompletion = 0;

  // 为每个 Tab 维护一个独立的 ScrollController
  final List<ScrollController> _scrollControllers = [
    ScrollController(),
    ScrollController(),
    ScrollController(),
  ];

  // 记录上次点击导航栏的时间，用于判断双击
  DateTime? _lastTapTime;

  @override
  void dispose() {
    for (final controller in _scrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _handleNavTap(int index) {
    final settings = context.read<SettingsController>().setting;

    if (_currentIndex == index) {
      // 如果点击的是当前选中的 Tab，检查是否是双击
      if (settings.doubleTapToTop) {
        final now = DateTime.now();
        if (_lastTapTime != null &&
            now.difference(_lastTapTime!) < const Duration(milliseconds: 300)) {
          // 触发双击回到顶部
          final controller = _scrollControllers[index];
          if (controller.hasClients) {
            controller.animateTo(
              0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
            );
          }
          _lastTapTime = null; // 重置时间
          return;
        }
        _lastTapTime = now;
      }
    } else {
      // 切换 Tab
      setState(() => _currentIndex = index);
      _lastTapTime = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AuthServices>();
    final postAuthSyncService = context.watch<PostAuthSyncService>();
    _handleSyncCompletion(postAuthSyncService);

    return FutureBuilder<bool>(
      future: context.read<AuthServices>().hasToken(),
      builder: (context, snapshot) {
        final hasToken = snapshot.data ?? false;

        final shellKey = ValueKey('AppShell-${hasToken ? "Auth" : "Guest"}');

        final pages = [
          JournalPage(scrollController: _scrollControllers[0]),
          FavPage(scrollController: _scrollControllers[1]),
          FeedPage(scrollController: _scrollControllers[2]),
        ];

        return Scaffold(
          key: shellKey,
          body: IndexedStack(index: _currentIndex, children: pages),
          bottomNavigationBar: NavigationBar(
            height: 64,
            selectedIndex: _currentIndex,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            onDestinationSelected: _handleNavTap,
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
