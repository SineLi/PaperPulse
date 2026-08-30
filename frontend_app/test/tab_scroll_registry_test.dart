import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/navigation/tab_scroll_registry.dart';

void main() {
  testWidgets('home double tap jumps to boundary when already at top', (
    tester,
  ) async {
    final controller = ScrollController();
    final registry = TabScrollRegistry();
    var boundaryCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemCount: 30,
          itemExtent: 80,
          itemBuilder: (_, index) => Text('Item $index'),
        ),
      ),
    );
    registry.register(feedTabIndex, controller);
    registry.registerContent(feedTabIndex, controller);
    registry.registerBoundaryScroller(feedTabIndex, () async {
      boundaryCalls += 1;
      return true;
    });

    await registry.handleDoubleTap(feedTabIndex);

    expect(boundaryCalls, 1);
    expect(controller.offset, 0);
  });

  testWidgets(
    'failed precise anchor does not trigger a conflicting scroll to top',
    (tester) async {
      final controller = ScrollController();
      final registry = TabScrollRegistry();

      await tester.pumpWidget(
        MaterialApp(
          home: ListView.builder(
            controller: controller,
            itemCount: 30,
            itemExtent: 80,
            itemBuilder: (_, index) => Text('Item $index'),
          ),
        ),
      );
      registry.register(feedTabIndex, controller);
      registry.registerContent(feedTabIndex, controller);
      registry.registerBoundaryScroller(feedTabIndex, () async {
        controller.jumpTo(400);
        return false;
      });

      await registry.handleDoubleTap(feedTabIndex);

      expect(controller.offset, 400);
    },
  );

  testWidgets('home double tap returns to top when list is scrolled', (
    tester,
  ) async {
    final controller = ScrollController();
    final registry = TabScrollRegistry();
    var boundaryCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemCount: 30,
          itemExtent: 80,
          itemBuilder: (_, index) => Text('Item $index'),
        ),
      ),
    );
    registry.register(feedTabIndex, controller);
    registry.registerContent(feedTabIndex, controller);
    registry.registerBoundaryScroller(feedTabIndex, () async {
      boundaryCalls += 1;
      return true;
    });
    controller.jumpTo(400);

    final scroll = registry.handleDoubleTap(feedTabIndex);
    await tester.pumpAndSettle();
    await scroll;

    expect(boundaryCalls, 0);
    expect(controller.offset, 0);
  });

  testWidgets('fraction scroll can reveal a lazily built anchor region', (
    tester,
  ) async {
    final controller = ScrollController();
    final registry = TabScrollRegistry();

    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemCount: 30,
          itemExtent: 80,
          itemBuilder: (_, index) => Text('Item $index'),
        ),
      ),
    );
    registry.register(feedTabIndex, controller);
    registry.registerContent(feedTabIndex, controller);

    final scroll = registry.scrollToFraction(feedTabIndex, 0.5);
    await tester.pumpAndSettle();

    expect(await scroll, isTrue);
    expect(controller.offset, greaterThan(0));
  });
}
