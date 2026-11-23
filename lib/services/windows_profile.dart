import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

Directory? _dataDirectory;

Future<Directory> gameDataDirectory() async =>
    _dataDirectory ?? await getApplicationSupportDirectory();

Future<void> initializeWindowsProfile() async {
  if (!Platform.isWindows) return;
  // path_provider resolves the Windows Known Folder, including redirection,
  // and appends CompanyName/ProductName from the executable's resources.
  final current = await getApplicationSupportDirectory();
  final legacy = Directory(
    '${current.parent.parent.path}/com.example/beastemu',
  );
  _dataDirectory = await prepareWindowsProfile(current, legacy);
}

/// Keep imported ROM paths, covers and loose settings in place on upgrades.
/// shared_preferences reads its own fixed path, so copy its one JSON file
/// before either preferences API opens it. Never modify the original.
Future<Directory> prepareWindowsProfile(
  Directory current,
  Directory legacy,
) async {
  if (!await legacy.exists()) return current;
  final source = File('${legacy.path}/shared_preferences.json');
  final target = File('${current.path}/shared_preferences.json');
  if (!await source.exists() || await target.exists()) return legacy;
  final lock = await File('${current.path}/migration.lock')
      .open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.blockingExclusive);
    if (await target.exists()) return legacy;
    final bytes = await source.readAsBytes();
    if (jsonDecode(utf8.decode(bytes)) is! Map<String, dynamic>) {
      throw const FormatException('Preferências antigas inválidas.');
    }
    final stage = await current.createTemp('.migrate-');
    try {
      final tmp = File('${stage.path}/shared_preferences.json');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(target.path);
    } finally {
      await stage.delete(recursive: true);
    }
    return legacy;
  } finally {
    await lock.close();
  }
}
