import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models/article.dart';
import '../data/repositories/feed_repo.dart';
import '../data/service/sync_service.dart';

import '../widgets/feed_card.dart';

class FeedPage extends StatefulWidget {
  final String username;
  const FeedPage({super.key, required this.username});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final ScrollController _scrollController = ScrollController();
  final List<Article> _articles = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _limit = 20;

  @override
  void initState() {
    super.initState();
    _loadMoreArticles();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_isLoading &&
          _hasMore) {
        _loadMoreArticles();
      }
    });
  }

  Future<void> _loadMoreArticles() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final feedRepo = context.read<FeedRepo>();
      final newArticles = await feedRepo.getLocalArticles(
        limit: _limit,
        offset: _currentOffset,
      );

      if (mounted) {
        setState(() {
          _currentOffset += newArticles.length;
          _articles.addAll(newArticles);
          _hasMore = newArticles.length == _limit;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading articles: $e')));
      }
    }
  }

  Future<void> _refreshArticles() async {
    // 只有在非加载状态下才允许刷新，或者你也可以允许中断当前加载
    if (_isLoading && _articles.isNotEmpty) return;

    setState(() {
      _isLoading = true;
      // 注意：刷新时不一定要清空列表，可以先保持旧数据，等新数据来了再替换
      // 但这里为了简单，我们选择清空并重置偏移量
    });

    try {
      final feedRepo = context.read<FeedRepo>();
      final syncService = context.read<SyncService>();

      // 1. 调用远程刷新接口，获取最新文章并存入数据库
      // refreshArticles() 方法应该返回新增文章数量，或者 void
      print(await feedRepo.refreshArticles());

      // 2. 刷新成功后，重置本地状态，重新加载第一页
      setState(() {
        _currentOffset = 0;
        _articles.clear();
        _hasMore = true;
        _isLoading = false; // 先设为 false，因为 _loadMoreArticles 会再次设为 true
      });

      // 3. 重新加载
      await _loadMoreArticles();

      // 4. 同步收藏等操作
      await syncService.pullStatus();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Latest Articles')),
      body: _articles.isEmpty && _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshArticles,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _articles.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _articles.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final article = _articles[index];
                  return FeedItemCard(article: article);
                },
              ),
            ),
    );
  }
}
