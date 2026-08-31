import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/data/models/article.dart';
import 'package:frontend_app/data/models/article_view_data.dart';
import 'package:frontend_app/widgets/feed_card.dart';

Article _readFavoriteArticle({
  bool isFavorite = true,
  int articleId = 1,
  String title = 'Article title',
  String maintag = '',
}) {
  return Article(
    articleId: articleId,
    title: title,
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
    maintag: maintag,
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

  testWidgets('compact, featured image, and masonry styles are selectable', (
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
                FeedItemCard(
                  article: _readFavoriteArticle(),
                  style: FeedCardStyle.masonry,
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
    expect(find.byKey(const ValueKey('feed-card-masonry')), findsOneWidget);
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

  testWidgets('compact maintag is omitted when it is blank', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              FeedItemCard(
                article: _readFavoriteArticle(maintag: '   '),
                style: FeedCardStyle.compact,
              ),
              FeedItemCard(
                article: _readFavoriteArticle(articleId: 2, maintag: ' 材料科学 '),
                style: FeedCardStyle.compact,
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('feed-card-compact-maintag')),
      findsOneWidget,
    );
    expect(find.text('材料科学'), findsOneWidget);
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

  testWidgets(
    'masonry card is compact for a grid and keeps read and favorite states',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.purple),
          home: Scaffold(
            body: SizedBox(
              width: 180,
              child: FeedItemCard(
                article: _readFavoriteArticle(),
                style: FeedCardStyle.masonry,
              ),
            ),
          ),
        ),
      );

      final card = tester.widget<Card>(
        find.byKey(const ValueKey('feed-card-masonry')),
      );
      final shape = card.shape! as RoundedRectangleBorder;

      expect(card.margin, EdgeInsets.zero);
      expect(shape.borderRadius, BorderRadius.circular(8));
      expect(shape.side.width, 1);
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.75);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.text('Article title'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Article title')).maxLines, 3);
      expect(
        tester.getSize(find.byKey(const ValueKey('feed-card-masonry'))).height,
        lessThanOrEqualTo(320),
      );
      expect(
        find.byKey(const ValueKey('feed-card-masonry-max-height')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ConstrainedBox>(
              find.byKey(const ValueKey('feed-card-masonry-max-height')),
            )
            .constraints
            .maxHeight,
        320,
      );
      expect(
        tester
            .widget<SizedBox>(
              find.byKey(const ValueKey('feed-card-masonry-image')),
            )
            .height,
        lessThanOrEqualTo(184),
      );
      expect(
        find.byKey(const ValueKey('feed-card-placeholder-gradient')),
        findsOneWidget,
      );
    },
  );

  testWidgets('masonry card can keep favorite items undimmed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: FeedItemCard(
              article: _readFavoriteArticle(),
              dimWhenRead: false,
              style: FeedCardStyle.masonry,
            ),
          ),
        ),
      ),
    );

    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  testWidgets('masonry image height varies stably and never exceeds its cap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 180,
                child: FeedItemCard(
                  article: _readFavoriteArticle(articleId: 1),
                  style: FeedCardStyle.masonry,
                ),
              ),
              SizedBox(
                width: 180,
                child: FeedItemCard(
                  article: _readFavoriteArticle(articleId: 2),
                  style: FeedCardStyle.masonry,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final imageHeights = tester
        .widgetList<SizedBox>(
          find.byKey(const ValueKey('feed-card-masonry-image')),
        )
        .map((widget) => widget.height)
        .toList();
    expect(imageHeights, [180, 144]);
  });

  testWidgets('masonry title keeps the first 23 Unicode characters visible', (
    tester,
  ) async {
    const title = '测试测试测试测试测试测试测试测试测试测试测试👩‍🔬后';
    final expectedTitle = title.characters.getRange(0, 23).toString();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: FeedItemCard(
              article: _readFavoriteArticle(title: title),
              style: FeedCardStyle.masonry,
            ),
          ),
        ),
      ),
    );

    final titleText = tester.widget<Text>(find.text(expectedTitle));
    expect(expectedTitle.characters.length, 23);
    expect(titleText.maxLines, 3);
    expect(titleText.overflow, TextOverflow.clip);
    expect(find.textContaining('后'), findsNothing);
  });

  testWidgets('masonry maintag is shown only when it has content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 180,
                child: FeedItemCard(
                  article: _readFavoriteArticle(maintag: '材料科学'),
                  style: FeedCardStyle.masonry,
                ),
              ),
              SizedBox(
                width: 180,
                child: FeedItemCard(
                  article: _readFavoriteArticle(articleId: 2),
                  style: FeedCardStyle.masonry,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('材料科学'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('feed-card-masonry-maintag')),
      findsOneWidget,
    );
  });
}
