import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/widgets/chunked_masonry_sliver.dart';

void main() {
  testWidgets('chunked masonry scrolls forward across a full-width boundary', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: controller,
            slivers: [
              ChunkedMasonrySliver(
                itemCount: 80,
                fullWidthLeading: const {
                  20: SizedBox(height: 40, child: Text('boundary')),
                },
                itemBuilder: _itemBuilder,
              ),
            ],
          ),
        ),
      ),
    );

    var previousOffset = controller.offset;
    for (var gesture = 0; gesture < 20; gesture++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(previousOffset));
      previousOffset = controller.offset;
    }
  });

  testWidgets('appending masonry items preserves the current scroll offset', (
    tester,
  ) async {
    final itemCount = ValueNotifier<int>(40);
    final controller = ScrollController();
    addTearDown(() {
      itemCount.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: itemCount,
            builder: (context, count, _) {
              return CustomScrollView(
                controller: controller,
                slivers: [
                  ChunkedMasonrySliver(
                    itemCount: count,
                    fullWidthLeading: const {
                      20: SizedBox(height: 40, child: Text('boundary')),
                    },
                    itemBuilder: _itemBuilder,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    controller.jumpTo(controller.position.maxScrollExtent - 200);
    await tester.pump();
    final offsetBeforeAppend = controller.offset;

    itemCount.value = 60;
    await tester.pump();

    expect(controller.offset, closeTo(offsetBeforeAppend, 0.1));
  });
}

Widget _itemBuilder(BuildContext context, int index) {
  return SizedBox(
    key: ValueKey('item-$index'),
    height: 180 + (index % 3) * 35,
    child: ColoredBox(color: Colors.blue, child: Text('item $index')),
  );
}
