import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/auth/auth_services.dart';
import '../data/models/user.dart';
import '../data/repositories/feed_repo.dart';
import '../data/repositories/journal_repo.dart';
import '../data/repositories/user_repo.dart';
import '../data/service/sync_service.dart';
import 'app_shell_page.dart';
import 'login_page.dart';

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

        if (snapshot.hasError) {
          // 网络错误但本地有 token → 仍然进入主界面（离线模式）
          return FutureBuilder<bool>(
            future: context.read<AuthServices>().hasToken(),
            builder: (context, tokenSnapshot) {
              if (tokenSnapshot.connectionState != ConnectionState.done) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (tokenSnapshot.data == true) {
                return const AppShellPage();
              }
              return const LoginPage();
            },
          );
        }

        return AppShellPage();
      },
    );
  }
}
