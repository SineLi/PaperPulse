import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/auth/auth_services.dart';
import '../data/models/user.dart';
import 'app_shell_page.dart';
import 'login_page.dart';

class BootstrapPage extends StatelessWidget {
  const BootstrapPage({super.key});

  @override
  Widget build(BuildContext context) {
    final authServices = context.read<AuthServices>();

    return FutureBuilder<User?>(
      future: authServices.tryGetCurrentUser(),
      builder: (context, snapshot) {
        // 启动加载中
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
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
