import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/auth/auth_services.dart';
import '../data/service/post_auth_sync_service.dart';
import '../router/app_router.dart';

class BootstrapPage extends StatefulWidget {
  const BootstrapPage({super.key});

  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authServices = context.read<AuthServices>();
      final postAuthSyncService = context.read<PostAuthSyncService>();
      unawaited(_bootstrap(authServices, postAuthSyncService));
    });
  }

  Future<void> _bootstrap(
    AuthServices authServices,
    PostAuthSyncService postAuthSyncService,
  ) async {
    context.go(homeFeedPath);

    try {
      final user = await authServices.tryGetCurrentUser();
      if (user != null) {
        unawaited(
          Future(() async {
            try {
              await postAuthSyncService.syncAfterAuth();
            } catch (e) {
              debugPrint('Background sync failed: $e');
            }
          }),
        );
      }
    } catch (e) {
      debugPrint('Bootstrap error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
