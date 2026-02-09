import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:provider/provider.dart';

import '../data/auth/auth_services.dart';
import '../data/service/feed_service.dart';
import '../data/db/articledb.dart';
import '../data/repositories/feed_repo.dart';

import '../widgets/feed_card.dart';

class FeedPage extends StatelessWidget {
  final String username;
  const FeedPage({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    final feedRepo = context.read<FeedRepo>();
    return Scaffold(
      body: Center(
        child: FutureBuilder<List<dynamic>>(
          future: feedRepo.getLocalArticles(limit: 1, offset: 10),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator();
            } else if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            } else if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              return FeedItemCard(article: snapshot.data![0]);
            } else {
              return const Text('No articles found');
            }
          },
        ),
      ),
    );
  }
}
