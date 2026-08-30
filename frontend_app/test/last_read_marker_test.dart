import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_app/widgets/last_read_marker.dart';

Widget buildSubject(Widget child) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: Colors.indigo,
    ),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('shows the default label', (tester) async {
    await tester.pumpWidget(buildSubject(const LastReadMarker()));

    expect(find.text('上次阅读到这'), findsOneWidget);
  });

  testWidgets('shows a custom label', (tester) async {
    await tester.pumpWidget(buildSubject(const LastReadMarker(label: '从这里继续')));

    expect(find.text('从这里继续'), findsOneWidget);
    expect(find.text('上次阅读到这'), findsNothing);
  });

  testWidgets('exposes its label as a semantic boundary', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(buildSubject(const LastReadMarker()));

    expect(tester.getSemantics(find.byType(LastReadMarker)).label, '上次阅读到这');
    semanticsHandle.dispose();
  });
}
