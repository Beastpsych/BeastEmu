import 'dart:async';
import 'dart:io';

import 'package:beastemu/services/sameboy_commands.dart';
import 'package:beastemu/services/sameboy_live_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/gba_demo.dart';
import 'sameboy_cartridge_integration_test.dart' show cartridge;

void main() {
  final package = Platform.environment['BEASTEMU_TEST_PACKAGE'];
  test('distribuição contém núcleos, auxiliares, créditos e somente arquivos de runtime', () async {
    final root = Directory(package!);
    for (final path in [
      'beastemu.exe',
      'beastemu_audio.dll',
      'flutter_windows.dll',
      'dartjni.dll',
      'data/app.so',
      'data/icudtl.dat',
      'helpers/sameboy-live.exe',
      'helpers/sameboy-preview.exe',
      'helpers/mgba-live.exe',
      'cores/windows/sameboy_libretro.dll',
      'cores/windows/mgba_libretro.dll',
      'LICENSE',
      'MARCA.md',
      'AVALIACAO.md',
      'GBA-DEV.md',
      'LEIA-ME.md',
      'licenses/mGBA.txt',
      'licenses/mGBA-inih.txt',
      'licenses/mGBA-FONTES.md',
      'licenses/SameBoy.txt',
      'licenses/Libretro.txt',
      'licenses/Dart.txt',
      'licenses/Flutter.txt',
      'data/flutter_assets/NOTICES.Z',
    ]) {
      expect(
        await File('${root.path}/$path').length(),
        greaterThan(0),
        reason: path,
      );
    }
    for (final core in ['sameboy', 'mgba']) {
      expect(
        await sha256
            .bind(
              File('${root.path}/cores/windows/${core}_libretro.dll')
                  .openRead(),
            )
            .first,
        await sha256
            .bind(File('cores/windows/${core}_libretro.dll').openRead())
            .first,
      );
    }
    final files = await root
        .list(recursive: true)
        .where((e) => e is File)
        .toList();
    expect(
      files.where(
        (e) => RegExp(
          r'\.(gba|gb|gbc|sav|cart|state|lock|log)$',
          caseSensitive: false,
        ).hasMatch(e.path),
      ),
      isEmpty,
    );
    expect(
      await File('${root.path}/licenses/mGBA-FONTES.md').readAsString(),
      contains('7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6'),
    );
  }, skip: package == null);

  test(
    'sessões alternadas GB, GBC, GBA encerram os auxiliares e recuperam estados isolados',
    () async {
      final temp = await Directory.systemTemp.createTemp('beast-integrated-');
      addTearDown(() => temp.delete(recursive: true));
      final roms = <File>[];
      for (final ext in ['gb', 'gbc', 'gba']) {
        final bytes = ext == 'gba' ? gbaDemo() : cartridge(ext == 'gbc');
        roms.add(await File('${temp.path}/synthetic.$ext').writeAsBytes(bytes));
      }
      for (var pass = 0; pass < 2; pass++) {
        for (final rom in roms) {
          final session = SameBoyLiveService(
            profileRoot: temp,
            appDirectory: Directory(package!),
          );
          final ready = Completer<void>();
          String? error;
          try {
            await session.start(
              romPath: rom.path,
              volume: 0,
              onFrame: (_) {
                if (!ready.isCompleted) ready.complete();
              },
              onError: (e) {
                error = e;
                if (!ready.isCompleted) ready.complete();
              },
            );
            await ready.future.timeout(const Duration(seconds: 15));
            expect(error, isNull);
            session.sendMask(256);
            session.sendMask(0);
            session.setSpeed(4);
            session.setSpeed(1);
            if (pass == 0) {
              await session.stateCommand(quickSave);
            } else {
              await session.stateCommand(quickLoad);
              expect(session.cartridgeProtected, isTrue);
            }
            expect(
              await session.stateCommand(listStateSlots),
              List.filled(5, null),
            );
          } finally {
            await session.stop();
          }
          // Opening the same cartridge in the following pass also proves its
          // exclusive lock was released by a fully stopped helper process.
        }
      }
      final base = '${temp.path}/BeastEmu-GBA-Dev/BeastEmu';
      for (final rom in roms) {
        final hash = sha256.convert(await rom.readAsBytes());
        final ns = rom.path.endsWith('.gba') ? 'mgba/' : '';
        expect(
          await File('$base/states/$ns$hash/quick.state').exists(),
          isTrue,
        );
      }
    },
    skip: package == null || !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
