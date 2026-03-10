import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/auth/auth_services.dart';
import '../data/models/user.dart';
import '../data/repositories/feed_repo.dart';
import '../data/repositories/journal_repo.dart';
import '../data/repositories/user_repo.dart';
import '../data/service/sync_service.dart';
import 'app_shell_page.dart';

class BootstrapPage extends StatefulWidget {
  const BootstrapPage({super.key});

  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  late final Future<User?> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    final authServices = context.read<AuthServices>();
    final journalRepo = context.read<JournalRepo>();
    final userRepo = context.read<UserRepo>();
    final feedRepo = context.read<FeedRepo>();
    final syncService = context.read<SyncService>();
    _bootstrapFuture = _bootstrap(
      authServices,
      journalRepo,
      userRepo,
      feedRepo,
      syncService,
    );
  }

  Future<User?> _bootstrap(
    AuthServices authServices,
    JournalRepo journalRepo,
    UserRepo userRepo,
    FeedRepo feedRepo,
    SyncService syncService,
  ) async {
    try {
      final user = await authServices.tryGetCurrentUser();
      if (user != null) {
        // 异步执行刷新操作，不阻塞启动
        Future(() async {
          try {
            await journalRepo.syncJournalsEmpty();
            await userRepo.syncSubscribedJournalIds();
            await syncService.flush();
            await syncService.pullStatus();
            await feedRepo.refreshArticles();
          } catch (e) {
            debugPrint('Background sync failed: $e');
          }
        });
      }
      return user;
    } catch (e) {
      debugPrint('Bootstrap error: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        // 启动加载中
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 无论是否登录，始终进入 AppShellPage
        // FeedPage 会根据 AuthServices.isLoggedIn 决定是否触发自动刷新
        return const AppShellPage();
      },
    );
  }
}
