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
    this.isFavorite = false,
    this.isRead = false,
  });

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
}
