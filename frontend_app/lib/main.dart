import 'package:flutter/widgets.dart';
import 'data/db/database.dart';

Future<void> main() async {
  print("Starting app...");
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.dbCheck();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Placeholder(),
    ),
  );
}
