import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/auth/auth_services.dart';
import '../data/models/user.dart';
import '../data/service/post_auth_sync_service.dart';
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
    final postAuthSyncService = context.read<PostAuthSyncService>();
    _bootstrapFuture = _bootstrap(authServices, postAuthSyncService);
  }

  Future<User?> _bootstrap(
    AuthServices authServices,
    PostAuthSyncService postAuthSyncService,
  ) async {
    try {
      final user = await authServices.tryGetCurrentUser();
      if (user != null) {
        // Keep startup responsive while post-auth sync continues in background.
        Future(() async {
          try {
            await postAuthSyncService.syncAfterAuth();
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
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return const AppShellPage();
      },
    );
  }
}
