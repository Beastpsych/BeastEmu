import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Run from the checkout after flutter build windows. Only runtime artifacts
/// from the release, the two helpers, notices and the tested core are bundled.
Future<void> main() async {
  if (!Platform.isWindows) throw UnsupportedError('Requer Windows x64.');
  final config = jsonDecode(
    await File('.dart_tool/package_config.json').readAsString(),
  ) as Map;
  final flutter = Directory.fromUri(Uri.parse(config['flutterRoot'] as String));
  final sdk = '${flutter.path}/bin/cache/dart-sdk';
  final release = Directory('build/windows/x64/runner/Release');
  final core = File('cores/windows/sameboy_libretro.dll');
  final hash = (await sha256.bind(core.openRead()).first).toString();
  if (hash !=
      '491aaf9074ef2f1cf641d87b3b17f44d488e648d111cd48825072d95916d7d7b') {
    throw StateError(
      'O núcleo mudou. Verifique ABI, estados e licença antes de empacotar.',
    );
  }
  final parent = await Directory('build/portable').create(recursive: true);
  final stage = await parent.createTemp('.staging-');
  Future<void> copy(String src, String dest) async {
    final target = File('${stage.path}/$dest');
    await target.parent.create(recursive: true);
    await File(src).copy(target.path);
  }

  for (final name in [
    'beastemu.exe',
    'flutter_windows.dll',
    'beastemu_audio.dll',
    'dartjni.dll',
    'data/icudtl.dat',
    'data/app.so',
  ]) {
    await copy('${release.path}/$name', name);
  }
  final assets = Directory('${release.path}/data/flutter_assets');
  await for (final item in assets.list(recursive: true, followLinks: false)) {
    if (item is File) {
      await copy(
        item.path,
        'data/flutter_assets/${item.path.substring(assets.path.length + 1)}',
      );
    }
  }
  await copy(core.path, 'cores/windows/sameboy_libretro.dll');
  await copy('LICENSE', 'LICENSE');
  await copy('MARCA.md', 'MARCA.md');
  await copy('docs/SameBoy-LICENSE.txt', 'licenses/SameBoy.txt');
  await copy('docs/Libretro-LICENSE.txt', 'licenses/Libretro.txt');
  await copy(
    'docs/Flutter-template-images-LICENSE.txt',
    'licenses/Flutter-template-images.txt',
  );
  await copy('docs/terceiros.md', 'licenses/CREDITOS.md');
  await copy(
    '${flutter.path}/bin/cache/artifacts/material_fonts/materialicons_license.txt',
    'licenses/MaterialIcons.txt',
  );
  final cupertino = (config['packages'] as List).singleWhere(
    (p) => p['name'] == 'cupertino_icons',
  );
  final packageConfig = File('.dart_tool/package_config.json').absolute.uri;
  final iconPackage = Directory.fromUri(
    packageConfig.resolve(cupertino['rootUri'] as String),
  );
  await copy('${iconPackage.path}/LICENSE', 'licenses/CupertinoIcons.txt');
  await copy('$sdk/LICENSE', 'licenses/Dart.txt');
  await copy('${flutter.path}/LICENSE', 'licenses/Flutter.txt');
  await copy(
    '${flutter.path}/bin/cache/artifacts/engine/windows-x64-release/license.windows_flutter.md',
    'licenses/Flutter-Windows.md',
  );
  await copy(
    '${flutter.path}/bin/cache/pkg/sky_engine/LICENSE',
    'licenses/Flutter-Engine.txt',
  );
  await copy('docs/windows-portatil.md', 'LEIA-ME.md');

  final helpers = await Directory('${stage.path}/helpers').create();
  for (final item in {
    'stream_sameboy': 'sameboy-live',
    'run_sameboy_frames': 'sameboy-preview',
  }.entries) {
    final result = await Process.run('$sdk/bin/dart.exe', [
      'compile',
      'exe',
      'tool/${item.key}.dart',
      '-o',
      '${helpers.path}/${item.value}.exe',
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'Compilação de ${item.key}: ${result.stdout}\n${result.stderr}',
      );
    }
  }
  final folder = await stage.rename(
    '${parent.path}/BeastEmu-Windows-x64-${DateTime.now().microsecondsSinceEpoch}',
  );
  stdout.writeln(folder.absolute.path);
}
