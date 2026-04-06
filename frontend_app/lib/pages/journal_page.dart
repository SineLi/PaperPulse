import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models/journal.dart';
import '../data/repositories/journal_repo.dart';
import '../data/repositories/user_repo.dart';
import '../data/service/post_auth_sync_service.dart';
import '../navigation/tab_scroll_registry.dart';
import '../widgets/journal_list_page.dart';

class JournalPage extends StatefulWidget {
  final ScrollController? scrollController;

  const JournalPage({super.key, this.scrollController});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  final Set<int> _followedIds = {};
  bool _initialized = false;
  int _lastExternalRefreshSignal = 0;

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
      if (mounted) {
        setState(() => _initialized = true);
      }
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
      if (mounted) {
        setState(() {});
      }
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
    final postAuthSyncService = context.watch<PostAuthSyncService>();
    _handleExternalRefreshSignal(postAuthSyncService.completedSyncCount);

    if (!_initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final journalRepo = context.read<JournalRepo>();

    return JournalListPage(
      title: '期刊',
      scrollController: widget.scrollController,
      tabScrollIndex: journalsTabIndex,
      loadJournals: (limit, offset, filter) => journalRepo.getLocalJournals(
        limit: limit,
        offset: offset,
        filter: filter,
      ),
      searchJournals: (query, limit, offset) =>
          journalRepo.searchLocalJournals(query, limit: limit, offset: offset),
      isFollowed: (journalId) => _followedIds.contains(journalId),
      onFollowChanged: _handleFollowChanged,
      loadFilterPublishers: journalRepo.getFilterablePublishers,
      loadFilterCasCategories: journalRepo.getFilterableCasCategories,
      showExternalRefreshing: postAuthSyncService.isSyncing,
      externalRefreshSignal: postAuthSyncService.completedSyncCount,
      onSettings: () {},
      emptyIcon: Icons.book_outlined,
      emptyTitle: '暂无期刊',
      emptySubtitle: '期刊数据尚未同步',
    );
  }

  void _handleExternalRefreshSignal(int signal) {
    if (_lastExternalRefreshSignal == signal) return;
    _lastExternalRefreshSignal = signal;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadFollowedIds());
    });
  }
}
