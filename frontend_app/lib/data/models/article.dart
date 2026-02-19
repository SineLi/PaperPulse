import 'dart:convert';

class Article {
  static const tableArticles = 'articles';
  static const colId = 'article_id';
  static const colTitle = 'title';
  static const colAbs = 'abs';
  static const colSummary = 'summary';
  static const colGAUrl = 'graphical_abstract_url';
  static const colGACachePath = 'graphical_abstract_cache_path';
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
  final String publishedDate;
  final List<String>? authors;
  final int journalId;
  final String journalName;
  final String journalAbbreviation;
  final String doi;
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
    required this.publishedDate,
    this.authors,
    required this.journalId,
    required this.journalName,
    required this.journalAbbreviation,
    required this.doi,
    this.publisher = '',
    this.isFavorite = false,
    this.isRead = false,
  });

  Article copyWith({
    String? publisher,
    bool? isFavorite,
    bool? isRead,
    String? graphicalAbstractCachePath,
  }) {
    return Article(
      articleId: articleId,
      title: title,
      abs: abs,
      summary: summary,
      graphicalAbstractUrl: graphicalAbstractUrl,
      graphicalAbstractCachePath:
          graphicalAbstractCachePath ?? this.graphicalAbstractCachePath,
      publishedDate: publishedDate,
      authors: authors,
      journalId: journalId,
      journalName: journalName,
      journalAbbreviation: journalAbbreviation,
      doi: doi,
      publisher: publisher ?? this.publisher,
      isFavorite: isFavorite ?? this.isFavorite,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, Object?> toMap() {
    return {
      colId: articleId,
      colTitle: title,
      colAbs: abs,
      colSummary: summary,
      colGAUrl: graphicalAbstractUrl,
      colGACachePath: graphicalAbstractCachePath,
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
      summary: map[colSummary] as String,
      graphicalAbstractUrl: map[colGAUrl] as String?,
      graphicalAbstractCachePath: map[colGACachePath] as String?,
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
    return Article(
      articleId: json['id'] as int,
      title: json['title'] as String,
      abs: json['abstract'] as String,
      summary: json['llm_summary'] as String,
      graphicalAbstractUrl: json['graphical_abstract'] as String?,
      graphicalAbstractCachePath: null,
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
