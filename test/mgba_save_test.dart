import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/mgba_save.dart';

void main() {
  late Directory root;
  late Uint8List memory;
  final rom = sha256.convert([1, 2, 3]).toString();
  Uint8List erased(int n) => Uint8List(n)..fillRange(0, n, 255);
  Future<MgbaSave> open() => MgbaSave.open(root, rom, () => memory, (_) {});
  File getIndex() => File('${root.path}/$rom/cart.json');
  Future<File> image([String key = 'current']) async {
    final m = jsonDecode(await getIndex().readAsString());
    return File('${root.path}/$rom/${m[key]}.sav');
  }

  Future<void> seed() async {
    final s = await open();
    memory = erased(32768)..[9] = 42;
    await s.close(flush: true);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('beast-mgba-store-');
    memory = erased(131072);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'Autodetecção silenciosa, geração anterior e restauração sem regravar',
    () async {
      await (await open()).close(flush: true);
      expect(await getIndex().exists(), false);
      await seed();
      memory = erased(131072);
      final second = await open();
      expect(memory[9], 42);
      final before = await getIndex().readAsBytes();
      await second.close(flush: true); // game never accessed cartridge
      expect(await getIndex().readAsBytes(), before);
      final third = await open();
      memory = Uint8List.fromList(memory.sublist(0, 32768))..[9] = 84;
      await third.close(flush: true);
      expect((await (await image('previous')).readAsBytes())[9], 42);
      expect((await (await image()).readAsBytes())[9], 84);
    },
  );
  test(
    'Save incompatível, corrompido ou desaparecido impede abertura e escrita',
    () async {
      await seed();
      final file = await image(), bytes = await file.readAsBytes();
      final manifest = await getIndex().readAsBytes();
      for (final wrong in [
        Uint8List(17),
        Uint8List.fromList(bytes)..[9] ^= 1,
      ]) {
        await file.writeAsBytes(wrong);
        await expectLater(open(), throwsFormatException);
        expect(await file.readAsBytes(), wrong);
        expect(await getIndex().readAsBytes(), manifest);
      }
      await file.writeAsBytes(bytes);
      await getIndex().delete();
      await expectLater(open(), throwsFormatException);
      expect(await file.readAsBytes(), bytes);
    },
  );
  test('Buffer vazio ou tipo divergente preserva o progresso', () async {
    await seed();
    final index = await getIndex().readAsBytes();
    for (final wrong in [
      erased(32768),
      Uint8List(32768),
      erased(512)..[0] = 77,
    ]) {
      memory = erased(131072);
      final s = await open();
      memory = wrong;
      await expectLater(s.close(flush: true), throwsStateError);
      expect(await getIndex().readAsBytes(), index);
      expect((await (await image()).readAsBytes())[9], 42);
    }
  });
  test(
    'Falha de publicação e imagem órfã preservam o último save confirmado',
    () async {
      await seed();
      final manifest = await getIndex().readAsBytes();
      final s = await open();
      memory[9] = 84;
      final dest = '${root.path}/$rom/${sha256.convert(memory)}.sav';
      final obstacle = await Directory(dest).create();
      await expectLater(
        s.close(flush: true),
        throwsA(isA<FileSystemException>()),
      );
      expect(await getIndex().readAsBytes(), manifest);
      await obstacle.delete();
      // Exact on-disk state of an interruption after raw image publication.
      await File(dest).writeAsBytes(memory);
      memory = erased(131072);
      await (await open()).close(flush: true);
      expect(memory[9], 42);
      expect(await getIndex().readAsBytes(), manifest);
    },
  );
  test(
    'Edição fora da sessão e segundo gravador não sobrescrevem o arquivo',
    () async {
      await seed();
      final s = await open();
      if (Platform.isWindows) {
        await expectLater(open(), throwsA(isA<FileSystemException>()));
      }
      final file = await image();
      final changed = await file.readAsBytes()
        ..[10] = 33;
      await file.writeAsBytes(changed);
      memory[9] = 99;
      s.tick();
      await expectLater(s.close(flush: true), throwsStateError);
      expect(await file.readAsBytes(), changed);
    },
  );
}
