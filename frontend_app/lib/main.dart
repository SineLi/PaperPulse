import 'package:flutter/widgets.dart';
import 'data/db/database.dart';
import 'data/models/article.dart';

Future<void> main() async {
  print("Starting app...");
  // await DatabaseHelper.instance.clearDatabase();

  WidgetsFlutterBinding.ensureInitialized();

  await DatabaseHelper.instance.addArticle(
    Article(
      articleId: 1,
      title: "Sample Article",
      abs: "This is an abstract.",
      summary: "This is a summary.",
      publishedDate: "2024-01-01",
      journalId: 1,
      journalName: "Sample Journal",
      journalAbbreviation: "SJ",
      doi: "10.1000/sampledoi",
    ),
  );

  await DatabaseHelper.instance.dbCheck();

  await DatabaseHelper.instance.getArticle(1).then((article) {
    if (article != null) {
      print("Retrieved Article: ${article.title}, DOI: ${article.doi}");
    } else {
      print("Article not found.");
    }
  });
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Placeholder(),
    ),
  );
}
