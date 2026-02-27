import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/auth/auth_services.dart';
import 'fav_page.dart';
import 'feed_page.dart';
import 'journal_page.dart';
import 'setting_page.dart';

class AppShellPage extends StatefulWidget {
  // final String username;
  const AppShellPage({super.key});

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  int _currentIndex = 2; // Default to Feed

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
    // Listen to AuthServices changes (login/logout)
    // This ensures the shell rebuilds when auth state changes
    context.watch<AuthServices>();

    // We can use a key that changes when auth state changes to force
    // refreshing the children states (like FeedPage's article list).
    // However, since we don't have a simple "auth version" property,
    // we can rely on the fact that `UnifiedListPage` (inside these pages)
    // will now re-check auth status because it's being rebuilt.
    //
    // But UnifiedListPage is likely checking auth via Provider in its own build method.
    // If the pages are kept alive by IndexedStack, their build method might NOT run
    // if only the parent rebuilds but passes same widget instances?
    // No, `pages` is recreated here. `FeedPage()` != `const FeedPage()` (unless verify const).
    // `FeedPage` is not const here. So new widget instance.
    // Flutter element update: if widget type same and key same, update render object.
    // State is kept.
    // So `FeedPage` state is kept.
    // We need to force state reset on logout.

    return FutureBuilder<bool>(
      future: context.read<AuthServices>().hasToken(),
      builder: (context, snapshot) {
        final hasToken = snapshot.data ?? false;

        // Use a key derived from auth state to force state destruction on logout/login.
        // This ensures that when user logs out, the pages (Feed, etc.) are recreated
        // and re-fetch data (which is now empty), clearing old cached content.
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
}
