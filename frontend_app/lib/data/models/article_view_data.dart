import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'article.dart';

Map<String, Color> tagColorMap = {
  'Wiley': Color(0xFF18C76F),
  'Springer Nature': Color(0xFF01324b),
  'Elsevier': Color(0xFFeb6500),
  'American Chemical Society': Color(0xFFffcd34),
  'Royal Society of Chemistry': Color(0xFF004976),
  'MDPI': Color(0xFF000000),
  'Taylor & Francis': Color(0xFF10147e),
  'AAAS': Color(0xFFca2015),
  'Frontiers': Color(0xFF8bc53f),
};

class ArticleViewData {
  final Article article;

  ArticleViewData({required this.article});

  factory ArticleViewData.fromArticle(Article article) {
    return ArticleViewData(article: article);
  }

  int get id => article.articleId;

  // 使用 Article 中解析好的 sumTitle，如果为空则显示原标题
  String? get displayTitle =>
      article.sumTitle.isNotEmpty ? article.sumTitle : article.title;

  String? get displayJournalName => article.journalAbbreviation;

  String get displayJournalInitials {
    String name = article.journalAbbreviation.isNotEmpty
        ? article.journalAbbreviation
        : article.journalName;

    String processed = name
        .replaceAll(RegExp(r'^Journal of ', caseSensitive: false), '')
        .trim();

    if (processed.isEmpty) return 'J';

    List<String> words = processed.split(RegExp(r'\s+'));
    if (words.length == 1) {
      return words[0][0].toUpperCase();
    }

    return (words[0][0] + words[1][0]).toUpperCase();
  }

  String? get displayOneStanceSum => article.oneSentenceSummary;
  String? get displayBackground => article.background;
  String? get displaySummary =>
      article.summary.isNotEmpty ? article.summary : article.abs;

  // 将字符串类型的 innovations 转回列表进行展示
  List<String>? get displayInnovations =>
      article.innovations.isNotEmpty ? article.innovations.split('\n') : null;

  String? get displayMaintag => article.maintag;
  List<String>? get displaySubtags => article.subtags;

  String? get publishedDate {
    if (article.publishedDate.isEmpty) return null;
    try {
      final date = DateTime.parse(article.publishedDate);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.isNegative) {
        return DateFormat.yMMMd().format(date);
      } else if (difference.inDays < 3) {
        return timeago.format(date);
      } else {
        return DateFormat.yMMMd().format(date);
      }
    } catch (_) {
      return article.publishedDate;
    }
  }

  Color get tagColor {
    String key = article.publisher;
    return tagColorMap[key] ?? Colors.grey;
  }

  String? get graphicalAbsUrl => article.graphicalAbstractUrl ?? '';
  String? get graphicalAbsCachePath => article.graphicalAbstractCachePath;

  bool get isRead => article.isRead;
  bool get isFavorite => article.isFavorite;
}
