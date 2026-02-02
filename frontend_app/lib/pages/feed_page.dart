import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/auth/auth_services.dart';

class FeedPage extends StatelessWidget {
  final String username;
  const FeedPage({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: const Center(child: Text('Feed page placeholder')));
  }
}
