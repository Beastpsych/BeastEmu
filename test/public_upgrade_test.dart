import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beastemu/services/windows_profile.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/audit_gba_import.dart';
import '../tool/cartridge_save.dart';
import 'support/gba_save_rom.dart';

void main() {
  test('identidade pública 0.2 conserva o AppId e o diretório da beta 0.1', () {
    final installer = File('windows/installer/beastemu.iss').readAsStringSync();
    expect(
      installer,
      contains('AppId={{EA0278D8-06C3-4CE8-9AC3-0219910142EE}'),
    );
    expect(
      installer,
      contains(r'DefaultDirName={localappdata}\Programs\BeastEmu'),
    );
    expect(installer, isNot(contains('Programs\\BeastEmu GBA Dev')));
    expect(
      File('windows/runner/Runner.rc').readAsStringSync(),
      contains('VALUE "ProductName", "BeastEmu"'),
    );
    expect(
      File('pubspec.yaml').readAsLinesSync(),
      contains('version: 0.2.0-beta.1+4'),
    );
  });
  test('upgrade público preserva bytes GB/GBC, RTC, slots, biblioteca e preferências 0.1', () async {
    final temp = await Directory.systemTemp.createTemp('beast-upgrade-');
    addTearDown(() => temp.delete(recursive: true));
    final current = await Directory('${temp.path}/roaming/BeastEmu/BeastEmu')
        .create(recursive: true);
    final legacy = Directory('${temp.path}/roaming/com.example/beastemu');
    final rom = Uint8List.fromList(List.generate(512, (i) => i & 255));
    final ram = Uint8List(32768), rtc = Uint8List(32);
    final store = await CartridgeSave.open(
      Directory('${temp.path}/local/BeastEmu/saves'),
      rom,
      ram,
      rtc,
    );
    ram[23] = 91;
    rtc[0] = 42;
    await store.close();
    for (final path in [
      'roaming/BeastEmu/BeastEmu/shared_preferences.json',
      'roaming/BeastEmu/BeastEmu/keyboard-bindings-v1.json',
      'roaming/BeastEmu/BeastEmu/emulation-settings-v1.json',
      'roaming/BeastEmu/BeastEmu/covers/test.png',
      'local/BeastEmu/states/rom/1.state',
      'local/BeastEmu/states/rom/quick.state',
    ]) {
      final f = File('${temp.path}/$path');
      await f.parent.create(recursive: true);
      await f.writeAsString(
        jsonEncode({
          'sentinel': path,
          'favorite': true,
          'recent': '2026-11-27',
          'gamepad': 1,
        }),
      );
    }
    final before = <String, String>{};
    await for (final f in temp.list(recursive: true)) {
      if (f is File) {
        before[f.path] = sha256.convert(await f.readAsBytes()).toString();
      }
    }
    expect((await prepareWindowsProfile(current, legacy)).path, current.path);
    final restored = await CartridgeSave.open(
      Directory('${temp.path}/local/BeastEmu/saves'),
      rom,
      Uint8List(32768),
      Uint8List(32),
    );
    await restored.close();
    for (final e in before.entries) {
      expect(
        sha256.convert(await File(e.key).readAsBytes()).toString(),
        e.value,
        reason: e.key,
      );
    }
  });

  test(
    'cópia manual GBA validada preserva origem, detecta corrupção e recusa núcleo ou ROM diferentes',
    () async {
      final package = Platform.environment['BEASTEMU_TEST_PACKAGE'];
      final temp = await Directory.systemTemp.createTemp('beast-import-');
      addTearDown(() => temp.delete(recursive: true));
      final rom = File('${temp.path}/synthetic.gba');
      final bytes = gbaSaveRom(32768);
      await rom.writeAsBytes(bytes);
      final dev = Directory('${temp.path}/dev');
      final seed = await Process.run('dart', [
        'run',
        'test/support/gba_state_frontend.dart',
        rom.path,
        dev.path,
        'save',
      ], runInShell: true);
      expect(seed.exitCode, 0, reason: '${seed.stderr}');
      final source = Directory('${dev.path}/BeastEmu-GBA-Dev/BeastEmu');
      final entries = await auditGbaImport(source, bytes);
      final target = Directory('${temp.path}/public/BeastEmu');
      final backup = Directory('${temp.path}/backup');
      // A pre-existing public file is backed up and is never overwritten.
      final conflict = File('${target.path}/${entries.keys.first}');
      await conflict.parent.create(recursive: true);
      await conflict.writeAsString('public sentinel');
      for (final entry in entries.entries) {
        final dest = File('${target.path}/${entry.key}');
        if (await dest.exists()) {
          final copy = File('${backup.path}/${entry.key}');
          await copy.parent.create(recursive: true);
          await dest.copy(copy.path);
          continue;
        }
        await dest.parent.create(recursive: true);
        await File('${source.path}/${entry.key}').copy(dest.path);
      }
      expect(await conflict.readAsString(), 'public sentinel');
      expect(
        await File('${backup.path}/${entries.keys.first}').readAsString(),
        'public sentinel',
      );
      // Resolve this synthetic conflict by choosing a fresh destination.
      final clean = Directory('${temp.path}/clean/BeastEmu');
      for (final entry in entries.entries) {
        final dest = File('${clean.path}/${entry.key}');
        await dest.parent.create(recursive: true);
        await File('${source.path}/${entry.key}').copy(dest.path);
      }
      expect(await auditGbaImport(clean, bytes), entries);
      final cartPath = entries.keys.firstWhere((p) => p.endsWith('.sav'));
      final cart = File('${clean.path}/$cartPath');
      final cartBackup = await cart.readAsBytes();
      final corruptCart = Uint8List.fromList(cartBackup)..[9] ^= 1;
      await cart.writeAsBytes(corruptCart);
      await expectLater(auditGbaImport(clean, bytes), throwsFormatException);
      expect(await cart.readAsBytes(), corruptCart);
      await cart.writeAsBytes(cartBackup);
      final id = sha256.convert(bytes);
      final state = File('${clean.path}/states/mgba/$id/quick.state');
      final original = await state.readAsBytes();
      final damaged = Uint8List.fromList(original)..[120] ^= 1;
      await state.writeAsBytes(damaged);
      await expectLater(auditGbaImport(clean, bytes), throwsFormatException);
      expect(await state.readAsBytes(), damaged);
      final otherCore = Uint8List.fromList(original)..[37] ^= 1;
      otherCore.setAll(
        otherCore.length - 32,
        sha256.convert(otherCore.sublist(0, otherCore.length - 32)).bytes,
      );
      await state.writeAsBytes(otherCore);
      await expectLater(auditGbaImport(clean, bytes), throwsFormatException);
      await state.writeAsBytes(original);
      await expectLater(
        auditGbaImport(clean, gbaSaveRom(32768, variant: 2)),
        throwsFormatException,
      );
      for (final entry in entries.entries) {
        expect(
          sha256
              .convert(await File('${source.path}/${entry.key}').readAsBytes())
              .toString(),
          entry.value,
        );
      }
      // Actual cartridge restoration from the manually copied files.
      final restore = await Process.run(
        'dart',
        [
          'run',
          'test/support/gba_public_frontend.dart',
          rom.path,
          '${temp.path}/clean',
        ],
        runInShell: true,
        environment: {
          'LOCALAPPDATA': '${temp.path}/clean',
          'BEASTEMU_TEST_PACKAGE': ?package,
        },
      );
      expect(restore.exitCode, 0, reason: '${restore.stderr}');
    },
    skip:
        !Platform.isWindows ||
        Platform.environment['BEASTEMU_TEST_PACKAGE'] == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
