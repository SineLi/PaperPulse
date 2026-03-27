import 'package:go_router/go_router.dart';

import '../pages/app_shell_page.dart';
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

GoRouter createAppRouter() {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const BootstrapPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingPage(),
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
