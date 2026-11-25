import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/gba_save_rom.dart';

void main() {
  for (final size in [512, 8192, 32768, 65536, 131072]) {
    test(
      'DLL mGBA: $size bytes, progresso no jogo após reiniciar o frontend e o núcleo',
      () async {
        final tmp = await Directory.systemTemp.createTemp('beast-gba-cart-');
        addTearDown(() => tmp.delete(recursive: true));
        final rom = File('${tmp.path}/teste.gba');
        final content = gbaSaveRom(size);
        await rom.writeAsBytes(content);
        final root = Directory(
          '${tmp.path}/BeastEmu-GBA-Dev/BeastEmu/saves/mgba',
        );
        final dir = Directory('${root.path}/${sha256.convert(content)}');
        Future<void> play(File file, String mode) async {
          final result = await Process.run('dart', [
            'run',
            'test/support/gba_save_frontend.dart',
            file.path,
            tmp.path,
            mode,
          ], runInShell: true);
          expect(
            result.exitCode,
            0,
            reason: '$size $mode: ${result.stdout} ${result.stderr}',
          );
        }

        await play(rom, size == 32768 ? 'periodic' : 'write');
        final meta = jsonDecode(
          await File('${dir.path}/cart.json').readAsString(),
        );
        final bytes = await File('${dir.path}/${meta['current']}.sav')
            .readAsBytes();
        expect(bytes.length, size);
        expect(sha256.convert(bytes).toString(), meta['current']);
        for (var i = 0; i < gbaProgress.length; i++) {
          final offset = switch (size) {
            512 => 0x12 * 8,
            8192 => 0x155 * 8,
            131072 when i >= 4 => 65536 + 0x234,
            _ => 0x234,
          };
          expect(bytes[offset + i], gbaProgress[i]);
        }
        final renamed = await rom.rename('${tmp.path}/renomeada.gba');
        await play(renamed, 'restore');
        if (size == 32768) {
          final distinct = File('${tmp.path}/outra.gba');
          await distinct.writeAsBytes(gbaSaveRom(size, variant: 1));
          await play(distinct, 'empty');
          await play(await renamed.copy('${tmp.path}/copia.gba'), 'restore');
        }
      },
      skip: !Platform.isWindows,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
