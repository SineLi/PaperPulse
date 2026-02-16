import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/auth/auth_services.dart';
import '../data/models/user.dart';
import '../data/repositories/journal_repo.dart';
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
    _bootstrapFuture = _bootstrap(authServices, journalRepo);
  }

  Future<User?> _bootstrap(
    AuthServices authServices,
    JournalRepo journalRepo,
  ) async {
    final user = await authServices.tryGetCurrentUser();
    if (user != null) {
      await journalRepo.syncJournalsEmpty();
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
          return const LoginPage();
        }

        // 已登录 -> Feed；未登录 -> Login
        final user = snapshot.data;
        if (user == null) {
          return const LoginPage();
        }
        return AppShellPage(username: user.username);
      },
    );
  }
}
