import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

Future<String> getAppDir() async {
  if (Platform.isWindows) {
    return p.dirname(Platform.resolvedExecutable);
  }
  final dir = await getApplicationSupportDirectory();
  return dir.path;
}

Future<String> getDbPath() async {
  final appDir = await getAppDir();
  final dbPath = Platform.isWindows
      ? p.join(appDir, '..', 'neko_db')
      : p.join(appDir, 'neko_db');
  await Directory(dbPath).create(recursive: true);
  return dbPath;
}

Future<String> getStoragePath() async {
  final appDir = await getAppDir();
  final storagePath = Platform.isWindows
      ? p.join(appDir, '..', 'neko_comics')
      : p.join(appDir, 'neko_comics');
  await Directory(storagePath).create(recursive: true);
  return storagePath;
}
