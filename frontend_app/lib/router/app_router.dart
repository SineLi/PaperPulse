import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../pages/app_shell_page.dart';
import '../pages/article_detail_page.dart';
import '../pages/bootstrap_page.dart';
import '../pages/fav_page.dart';
import '../pages/feed_page.dart';
import '../pages/journal_page.dart';
import '../pages/login_page.dart';
import '../pages/setting_page.dart';
import '../pages/signup_page.dart';

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
        routes: [
          GoRoute(
            path: 'account',
            builder: (context, state) => const AccountSettingsPage(),
          ),
          GoRoute(
            path: 'theme',
            builder: (context, state) => const ThemeSettingsPage(),
          ),
          GoRoute(
            path: 'network',
            builder: (context, state) => const NetworkSettingsPage(),
          ),
          GoRoute(
            path: 'operation',
            builder: (context, state) => const OperationSettingsPage(),
          ),
          GoRoute(
            path: 'experimental',
            builder: (context, state) => const ExperimentalPage(),
          ),
          GoRoute(
            path: 'about',
            builder: (context, state) => const AboutPage(),
            routes: [
              GoRoute(
                path: 'licenses',
                builder: (context, state) => const LicensePage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/article/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final idText = state.pathParameters['id']!;
          final articleId = int.tryParse(idText);
          if (articleId == null) {
            return ArticleNotFoundPage(
              message: '无效的文章 ID：$idText',
            );
          }

          final source = normalizeArticleSource(
            state.uri.queryParameters['source'],
          );
          final onArticleRead = state.extra;

          return ArticleDetailPage(
            articleId: articleId,
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
