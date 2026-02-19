import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/auth/auth_services.dart';
import 'fav_page.dart';
import 'feed_page.dart';
import 'journal_page.dart';

class AppShellPage extends StatefulWidget {
  // final String username;
  const AppShellPage({super.key});

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  int _currentIndex = 2; // Default to Feed

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

        final pages = [const JournalPage(), const FavPage(), const FeedPage()];

        return Scaffold(
          key: shellKey,
          body: IndexedStack(index: _currentIndex, children: pages),
          bottomNavigationBar: NavigationBar(
            height: 64,
            selectedIndex: _currentIndex,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            onDestinationSelected: (index) {
              setState(() => _currentIndex = index);
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
}

class _PlaceholderTab extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _PlaceholderTab({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
