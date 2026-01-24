import 'package:flutter/widgets.dart';
import 'data/db/database.dart';
import 'data/models/article.dart';
import 'data/db/articledb.dart';

Future<void> main() async {
  print("Starting app...");
  WidgetsFlutterBinding.ensureInitialized();
  final aIO = ArticleDatabaseIO();
  List<Article> testArticles = [
    Article(
      articleId: 1,
      title: "Test Article",
      abs: "This is an abstract.",
      summary: "This is a summary.",
      publishedDate: "2024-01-01",
      journalId: 1,
      journalName: "Test Journal",
      journalAbbreviation: "TJ",
      doi: "10.1000/testdoi",
    ),
    Article(
      articleId: 2,
      title: "Test Article 2",
      abs: "Abstract 2",
      summary: "Summary 2",
      publishedDate: "2024-02-01",
      journalId: 2,
      journalName: "Test Journal 2",
      journalAbbreviation: "TJ2",
      doi: "10.1000/testdoi2",
    ),
  ];
  await aIO.addArticles(testArticles);
  List<Article> testList = await aIO.getArticles(10, 0);
  print("Retrieved Articles:");
  for (var article in testList) {
    print("ID: ${article.articleId}, Title: ${article.title}");
  }
  await aIO.setFavorite(1, true);
  await aIO.setRead(1, true);
  await aIO.dbHelper.dbCheck();

  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Placeholder(),
    ),
  );
}
