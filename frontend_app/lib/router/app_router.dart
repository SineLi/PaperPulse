import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../pages/app_shell_page.dart';
import '../pages/article_detail_page.dart';
import '../pages/bootstrap_page.dart';
import '../pages/login_page.dart';
import '../pages/setting_page.dart';
import '../pages/signup_page.dart';

import '../pages/fav_page.dart';
import '../pages/feed_page.dart';
import '../pages/journal_page.dart';

const homePath = '/home';
const homeFeedPath = '/home/feed';
const homeFavoritesPath = '/home/favorites';
const homeJournalsPath = '/home/journals';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createAppRouter() {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const BootstrapPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/register',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SettingPage(),
      ),
      GoRoute(
        path: '/article/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          // URL 里只保留稳定状态。source 只提供最小上下文，
          // 让详情页能在本地重建上一篇/下一篇的文章 ID 列表。
          final source = normalizeArticleSource(
            state.uri.queryParameters['source'],
          );
          final onArticleRead = state.extra;
          return ArticleDetailPage(
            articleId: int.parse(id),
            source: source,
            onArticleRead: onArticleRead is void Function(int)
                ? onArticleRead
                : null,
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShellPage(
            currentIndex: navigationShell.currentIndex,
            navigationShell: navigationShell,
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: homeJournalsPath,
                builder: (context, state) => const JournalPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: homeFavoritesPath,
                builder: (context, state) => const FavPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: homeFeedPath,
                builder: (context, state) => const FeedPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
