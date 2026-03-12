import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

Future<void> initializeDatabasePlatform() async {}

Future<String> resolveDatabasePath(String fileName) async {
  final appDir = await getApplicationDocumentsDirectory();
  return join(appDir.path, fileName);
}
