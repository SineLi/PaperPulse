import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models/journal.dart';
import '../data/repositories/journal_repo.dart';
import '../data/repositories/user_repo.dart';
import '../widgets/journal_list_page.dart';

class JournalPage extends StatefulWidget {
  const JournalPage({super.key});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  /// 本地已关注的期刊 ID 集合（快速查找）
  final Set<int> _followedIds = {};
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _loadFollowedIds();
  }

  Future<void> _loadFollowedIds() async {
    final userRepo = context.read<UserRepo>();
    try {
      final ids = await userRepo.fetchSubscribedJournalIds();
      if (mounted) {
        setState(() {
          _followedIds
            ..clear()
            ..addAll(ids);
          _initialized = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _initialized = true);
    }
  }

  Future<void> _handleFollowChanged(Journal journal, bool follow) async {
    final userRepo = context.read<UserRepo>();
    try {
      if (follow) {
        await userRepo.followJournal(journal.journalId);
        _followedIds.add(journal.journalId);
      } else {
        await userRepo.unfollowJournal(journal.journalId);
        _followedIds.remove(journal.journalId);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(follow ? '关注失败: $e' : '取消关注失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final journalRepo = context.read<JournalRepo>();

    return JournalListPage(
      title: '期刊',
      loadJournals: (limit, offset) =>
          journalRepo.getLocalJournals(limit: limit, offset: offset),
      searchJournals: (query, limit, offset) =>
          journalRepo.searchLocalJournals(query, limit: limit, offset: offset),
      isFollowed: (journalId) => _followedIds.contains(journalId),
      onFollowChanged: _handleFollowChanged,
      onFilter: () {
        // TODO: implement journal filter bottom sheet
      },
      onSettings: () {
        // TODO: implement settings
      },
      emptyIcon: Icons.book_outlined,
      emptyTitle: '暂无期刊',
      emptySubtitle: '期刊数据尚未同步',
    );
  }
}
