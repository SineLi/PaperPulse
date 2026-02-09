import 'dart:convert';
import 'article.dart';

class ArticleSummary {
  final String? title;
  final String? summary;
  final String? highlights;
  final List<String>? innovations;
  final String? maintag;
  final List<String>? subtags;

  ArticleSummary({
    required this.title,
    required this.summary,
    required this.highlights,
    required this.innovations,
    required this.maintag,
    required this.subtags,
  });

  factory ArticleSummary.fromJson(String jsonStr) {
    try {
      final json = jsonDecode(jsonStr);
      if (json is! Map<String, dynamic>) {
        return ArticleSummary(
          title: null,
          summary: null,
          highlights: null,
          innovations: null,
          maintag: null,
          subtags: null,
        );
      }

      List<String>? _list(dynamic v) {
        if (v is List) return v.map((e) => e.toString()).toList();
        return null;
      }

      return ArticleSummary(
        title: json['title']?.toString(),
        summary: json['summary']?.toString(),
        highlights: json['highlights']?.toString(),
        innovations: _list(json['innovations']),
        maintag: json['maintag']?.toString(),
        subtags: _list(json['subtags']),
      );
    } catch (_) {
      return ArticleSummary(
        title: null,
        summary: null,
        highlights: null,
        innovations: null,
        maintag: null,
        subtags: null,
      );
    }
  }
}

class ArticleViewData {
  final Article article;
  final ArticleSummary summary;

  ArticleViewData({required this.article, required this.summary});

  factory ArticleViewData.fromArticle(Article article) {
    return ArticleViewData(
      article: article,
      summary: ArticleSummary.fromJson(article.summary),
    );
  }

  int get id => article.articleId;
  String? get displayTitle => summary.title ?? article.title;
  String? get displayJournalName => article.journalAbbreviation;
  String? get displaySummary => summary.summary ?? article.abs;
  String? get displayHighlights => summary.highlights;
  List<String>? get displayInnovations => summary.innovations;
  String? get displayMaintag => summary.maintag;
  List<String>? get displaySubtags => summary.subtags;
  String? get publishedDate => article.publishedDate;

  bool get isRead => article.isRead;
  bool get isFavorite => article.isFavorite;
}
