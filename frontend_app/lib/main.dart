import 'package:flutter/widgets.dart';
import 'data/db/database.dart';
import 'data/db/syncdb.dart';

Future<void> main() async {
  print("Starting app...");
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("Resetting database for development...");
  await DatabaseHelper.instance.resetDatabaseForDev();
  final syncIO = SyncDatabaseIO();

  await syncIO.addSyncAction(1, 'favorite');
  await syncIO.addSyncAction(2, 'read');
  final actions = await syncIO.getPendingSyncActions();
  print("Pending sync actions: $actions");

  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Placeholder(),
    ),
  );
}
