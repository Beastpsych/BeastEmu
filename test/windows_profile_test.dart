import 'dart:convert';
import 'dart:io';

import 'package:beastemu/core/version.dart';
import 'package:beastemu/services/windows_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late Directory current;
  late Directory legacy;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('beast-profile ');
    current = await Directory('${temp.path}/BeastEmu/BeastEmu')
        .create(recursive: true);
    legacy = Directory('${temp.path}/com.example/beastemu');
  });
  tearDown(() => temp.delete(recursive: true));

  test('instalação nova começa no perfil BeastEmu', () async {
    expect((await prepareWindowsProfile(current, legacy)).path, current.path);
    expect(await legacy.exists(), isFalse);
  });

  test(
    'atualização mantém arquivos e caminhos, sem substituir preferências novas',
    () async {
      await legacy.create(recursive: true);
      final rom = File('${legacy.path}/beastemu_roms/demo.gb');
      await rom.parent.create();
      await rom.writeAsBytes([0, 1]);
      final preferences = jsonEncode({
        'beastemu.gameboy.library.v1': jsonEncode([
          {'localPath': rom.path},
        ]),
        'flutter.previous': ['a', 'b'],
      });
      final old = File('${legacy.path}/shared_preferences.json');
      await old.writeAsString(preferences);
      final migrated = File('${current.path}/shared_preferences.json');
      expect((await prepareWindowsProfile(current, legacy)).path, legacy.path);
      expect(await migrated.readAsString(), preferences);
      expect(await rom.readAsBytes(), [0, 1]);
      await migrated.writeAsString('{"new": true}');
      await prepareWindowsProfile(current, legacy);
      expect(await migrated.readAsString(), '{"new": true}');
      expect(await old.readAsString(), preferences);
    },
  );

  test(
    'falha de leitura permite retomar a migração com o original preservado',
    () async {
      await legacy.create(recursive: true);
      final old = File('${legacy.path}/shared_preferences.json');
      await old.writeAsString('{');
      await expectLater(
        prepareWindowsProfile(current, legacy),
        throwsFormatException,
      );
      expect(await old.readAsString(), '{');
      expect(
        await File('${current.path}/shared_preferences.json').exists(),
        isFalse,
      );
      await old.writeAsString('{}');
      await prepareWindowsProfile(current, legacy);
      expect(
        await File('${current.path}/shared_preferences.json').readAsString(),
        '{}',
      );
    },
  );

  test('a versão da interface acompanha a versão distribuída', () {
    expect(
      File('pubspec.yaml').readAsLinesSync(),
      contains('version: $beastEmuVersion'),
    );
  });
}
