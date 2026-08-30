import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/data/models/article.dart';
import 'package:frontend_app/data/models/article_view_data.dart';
import 'package:frontend_app/widgets/feed_card.dart';

Article _readFavoriteArticle({bool isFavorite = true}) {
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
    isFavorite: isFavorite,
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
    expect(
      find.byKey(const ValueKey('feed-card-featuredImage')),
      findsOneWidget,
    );
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

  testWidgets('compact and featured image styles are selectable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                FeedItemCard(
                  article: _readFavoriteArticle(),
                  style: FeedCardStyle.compact,
                ),
                FeedItemCard(
                  article: _readFavoriteArticle(),
                  style: FeedCardStyle.featuredImage,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('feed-card-compact')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('feed-card-featuredImage')),
      findsOneWidget,
    );
  });

  testWidgets('featured image style reflects the favorite state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedItemCard(article: _readFavoriteArticle(isFavorite: false)),
        ),
      ),
    );

    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
  });

  testWidgets('featured image card has a subtle outer outline only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.teal),
        home: Scaffold(body: FeedItemCard(article: _readFavoriteArticle())),
      ),
    );

    final colorScheme = Theme.of(
      tester.element(find.byType(Scaffold)),
    ).colorScheme;
    final card = tester.widget<Card>(
      find.byKey(const ValueKey('feed-card-featuredImage')),
    );
    final shape = card.shape! as RoundedRectangleBorder;

    expect(shape.side.width, 1);
    expect(shape.side.color, colorScheme.outlineVariant.withValues(alpha: 0.5));
    expect(
      find.byKey(const ValueKey('feed-card-featured-header')),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).border != null,
      ),
      findsNothing,
    );
  });

  testWidgets('compact card has no outer outline', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedItemCard(
            article: _readFavoriteArticle(),
            style: FeedCardStyle.compact,
          ),
        ),
      ),
    );

    final card = tester.widget<Card>(
      find.byKey(const ValueKey('feed-card-compact')),
    );
    final shape = card.shape! as RoundedRectangleBorder;

    expect(shape.side, BorderSide.none);
  });

  testWidgets(
    'featured image placeholder softly derives from publisher color',
    (tester) async {
      final article = _readFavoriteArticle();
      final publisherColor = ArticleViewData.fromArticle(article).tagColor;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.blue),
          home: Scaffold(body: FeedItemCard(article: article)),
        ),
      );

      final colorScheme = Theme.of(
        tester.element(find.byType(Scaffold)),
      ).colorScheme;
      final placeholder = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('feed-card-placeholder-gradient')),
      );
      final gradient =
          (placeholder.decoration as BoxDecoration).gradient! as LinearGradient;

      expect(
        gradient.colors,
        contains(Color.lerp(publisherColor, colorScheme.surface, 0.78)),
      );
      expect(
        gradient.colors,
        contains(Color.lerp(publisherColor, colorScheme.surface, 0.58)),
      );
    },
  );
}
