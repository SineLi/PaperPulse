import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

bool _initialized = false;

Future<void> initializeDatabasePlatform() async {
  if (_initialized) {
    return;
  }

  databaseFactory = databaseFactoryFfiWeb;
  _initialized = true;
}

Future<String> resolveDatabasePath(String fileName) async {
  return fileName;
}
