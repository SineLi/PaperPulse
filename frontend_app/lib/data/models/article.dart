import 'dart:convert';

class Article {
  static const tableArticles = 'articles';
  static const colId = 'article_id';
  static const colTitle = 'title';
  static const colAbs = 'abs';
  static const colSumTitle = 'sum_title';
  static const colOneSentenceSummary = 'one_sentence_summary';
  static const colBackground = 'background';
  static const colSummary = 'summary';
  static const colInnovations = 'innovations';
  static const colMaintag = 'maintag';
  static const colSubtags = 'subtags';
  static const colGAUrl = 'graphical_abstract_url';
  static const colGACachePath = 'graphical_abstract_cache_path';
  static const colGAFallbackUrl = 'graphical_abstract_fallback_url';
  static const colPublishedDate = 'published_date';
  static const colAuthors = 'authors';
  static const colJournalId = 'journal_id';
  static const colJournalName = 'journal_name';
  static const colJournalAbbr = 'journal_abbreviation';
  static const colDoi = 'doi';
  static const colIsFavorite = 'is_favorite';
  static const colIsRead = 'is_read';

  final int articleId;
  final String title;
  final String abs;
  final String summary;
  final String? graphicalAbstractUrl;
  final String? graphicalAbstractCachePath;
  final String? graphicalAbstractFallbackUrl;
  final String publishedDate;
  final List<String>? authors;
  final int journalId;
  final String journalName;
  final String journalAbbreviation;
  final String doi;
  final String sumTitle;
  final String oneSentenceSummary;
  final String background;
  final String innovations;
  final String maintag;
  final List<String> subtags;
  final String publisher;
  final bool isFavorite;
  final bool isRead;

  Article({
    required this.articleId,
    required this.title,
    required this.abs,
    required this.summary,
    this.graphicalAbstractUrl,
    this.graphicalAbstractCachePath,
    this.graphicalAbstractFallbackUrl,
    required this.publishedDate,
    this.authors,
    required this.journalId,
    required this.journalName,
    required this.journalAbbreviation,
    required this.doi,
    required this.sumTitle,
    required this.oneSentenceSummary,
    required this.background,
    required this.innovations,
    required this.maintag,
    required this.subtags,
    this.publisher = '',
    this.isFavorite = false,
    this.isRead = false,
  });

  Article copyWith({
    String? publisher,
    bool? isFavorite,
    bool? isRead,
    String? graphicalAbstractCachePath,
    String? graphicalAbstractFallbackUrl,
  }) {
    return Article(
      articleId: articleId,
      title: title,
      abs: abs,
      summary: summary,
      graphicalAbstractUrl: graphicalAbstractUrl,
      graphicalAbstractCachePath:
          graphicalAbstractCachePath ?? this.graphicalAbstractCachePath,
      graphicalAbstractFallbackUrl:
          graphicalAbstractFallbackUrl ?? this.graphicalAbstractFallbackUrl,
      publishedDate: publishedDate,
      authors: authors,
      journalId: journalId,
      journalName: journalName,
      journalAbbreviation: journalAbbreviation,
      doi: doi,
      publisher: publisher ?? this.publisher,
      isFavorite: isFavorite ?? this.isFavorite,
      isRead: isRead ?? this.isRead,
      sumTitle: sumTitle,
      oneSentenceSummary: oneSentenceSummary,
      background: background,
      innovations: innovations,
      maintag: maintag,
      subtags: subtags,
    );
  }

  Map<String, Object?> toMap() {
    return {
      colId: articleId,
      colTitle: title,
      colAbs: abs,
      colSummary: summary,
      colSumTitle: sumTitle,
      colOneSentenceSummary: oneSentenceSummary,
      colBackground: background,
      colInnovations: jsonEncode(innovations),
      colMaintag: maintag,
      colSubtags: jsonEncode(subtags),
      colGAUrl: graphicalAbstractUrl,
      colGACachePath: graphicalAbstractCachePath,
      colGAFallbackUrl: graphicalAbstractFallbackUrl,
      colPublishedDate: publishedDate,
      colAuthors: authors != null ? jsonEncode(authors) : null,
      colJournalId: journalId,
      colJournalName: journalName,
      colJournalAbbr: journalAbbreviation,
      colDoi: doi,
      colIsFavorite: isFavorite ? 1 : 0,
      colIsRead: isRead ? 1 : 0,
    };
  }

  factory Article.fromMap(Map<String, Object?> map) {
    return Article(
      articleId: map[colId] as int,
      title: map[colTitle] as String,
      abs: map[colAbs] as String,
      sumTitle: map[colSumTitle] as String,
      oneSentenceSummary: map[colOneSentenceSummary] as String,
      background: map[colBackground] as String,
      innovations: jsonDecode(map[colInnovations] as String),
      maintag: map[colMaintag] as String,
      subtags: List<String>.from(jsonDecode(map[colSubtags] as String)),
      summary: map[colSummary] as String,
      graphicalAbstractUrl: map[colGAUrl] as String?,
      graphicalAbstractCachePath: map[colGACachePath] as String?,
      graphicalAbstractFallbackUrl: map[colGAFallbackUrl] as String?,
      publishedDate: map[colPublishedDate] as String,
      authors: map[colAuthors] != null
          ? List<String>.from(jsonDecode(map[colAuthors] as String))
          : null,
      journalId: map[colJournalId] as int,
      journalName: map[colJournalName] as String,
      journalAbbreviation: map[colJournalAbbr] as String,
      doi: map[colDoi] as String,
      isFavorite: (map[colIsFavorite] as int) == 1,
      isRead: (map[colIsRead] as int) == 1,
    );
  }

  factory Article.fromJson(Map<String, dynamic> json) {
    final llmSummaryStr = json['llm_summary'] as String;
    final llmMap = jsonDecode(llmSummaryStr) as Map<String, dynamic>;

    return Article(
      articleId: json['id'] as int,
      title: json['title'] as String,
      abs: json['abstract'] as String,
      summary: llmMap['summary'] as String,
      sumTitle: llmMap['title'] as String,
      oneSentenceSummary: llmMap['one_sentence_summary'] as String,
      background: llmMap['background'] as String,
      innovations: (llmMap['innovations'] as List).join('\n'),
      maintag: llmMap['maintag'] as String,
      subtags: List<String>.from(llmMap['subtags'] as List),
      graphicalAbstractUrl: json['graphical_abstract'] as String?,
      graphicalAbstractCachePath: null,
      graphicalAbstractFallbackUrl:
          json['graphical_abstract_cached_url'] as String?,
      publishedDate: json['date'] as String,
      authors: json['authors'] != null
          ? List<String>.from(json['authors'] as List)
          : null,
      journalId: json['journal_id'] as int,
      journalName: json['journal_name'] as String,
      journalAbbreviation: json['abbreviation'] as String,
      doi: json['doi'] as String,
      isFavorite: false,
      isRead: false,
    );
  }
}
