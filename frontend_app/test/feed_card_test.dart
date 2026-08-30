import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/data/models/article.dart';
import 'package:frontend_app/widgets/feed_card.dart';

Article _readFavoriteArticle() {
  return Article(
    articleId: 1,
    title: 'Article title',
    abs: 'Abstract',
    summary: 'Summary',
    publishedDate: '2026-08-30',
    journalId: 1,
    journalName: 'Journal',
    journalAbbreviation: 'J.',
    doi: '10.0000/example',
    sumTitle: '',
    oneSentenceSummary: '',
    background: '',
    innovations: '',
    maintag: '',
    subtags: const [],
    isFavorite: true,
    isRead: true,
  );
}

void main() {
  testWidgets('read cards can opt out of dimming in favorites', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedItemCard(
            article: _readFavoriteArticle(),
            dimWhenRead: false,
          ),
        ),
      ),
    );

    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  testWidgets('read cards remain dimmed by default', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FeedItemCard(article: _readFavoriteArticle())),
      ),
    );

    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.75);
  });
}
