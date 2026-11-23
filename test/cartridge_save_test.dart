import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../tool/cartridge_save.dart';

void main() {
  late Directory dir;
  final rom = Uint8List.fromList([1, 2, 3]);
  late Uint8List ram, rtc;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cart-test-');
    ram = Uint8List(8);
    rtc = Uint8List(4);
  });
  tearDown(() => dir.delete(recursive: true));

  test('restores both regions; close waits for an older checkpoint', () async {
    final s = await CartridgeSave.open(dir, rom, ram, rtc);
    ram[1] = 2;
    final first = s.checkpoint();
    ram[1] = 3;
    rtc[3] = 9;
    await s.close();
    await first;
    ram.fillRange(0, ram.length, 0);
    rtc.fillRange(0, rtc.length, 0);
    final reopened = await CartridgeSave.open(dir, rom, ram, rtc);
    expect(ram[1], 3);
    expect(rtc[3], 9);
    final modified = await s.file.lastModified();
    await reopened.close();
    expect(await s.file.lastModified(), modified);
  });

  test('isolates ROM identities and supports RTC-only cartridges', () async {
    final s = await CartridgeSave.open(dir, rom, Uint8List(0), rtc);
    rtc[0] = 42;
    await s.close();
    final other = await CartridgeSave.open(
      dir,
      Uint8List(2),
      Uint8List(0),
      Uint8List(4),
    );
    expect(other.file.path, isNot(s.file.path));
    await other.close();
    expect(await other.file.exists(), isFalse);
    final clock = Uint8List(4);
    await (await CartridgeSave.open(dir, rom, Uint8List(0), clock)).close();
    expect(clock[0], 42);
  });

  test('refuses wrong sizes, corrupt content and unreadable saves', () async {
    final s = await CartridgeSave.open(dir, rom, ram, rtc);
    ram[0] = 9;
    await s.close();
    final original = await s.file.readAsBytes();
    await expectLater(
      CartridgeSave.open(dir, rom, Uint8List(7), rtc),
      throwsA(isA<FileSystemException>()),
    );
    expect(await s.file.readAsBytes(), original);
    final broken = Uint8List.fromList(original);
    broken.last ^= 1;
    await s.file.writeAsBytes(broken);
    ram[0] = 0;
    await expectLater(
      CartridgeSave.open(dir, rom, ram, rtc),
      throwsA(isA<FileSystemException>()),
    );
    expect(ram[0], 0);
    expect(await s.file.readAsBytes(), broken);
    await s.file.delete();
    await Directory(s.file.path).create();
    await expectLater(
      CartridgeSave.open(dir, rom, ram, rtc),
      throwsA(isA<FileSystemException>()),
    );
    expect(await Directory(s.file.path).exists(), isTrue);
  });

  test(
    'protects an external replacement and refuses simultaneous sessions',
    () async {
      final s = await CartridgeSave.open(dir, rom, ram, rtc);
      late Uint8List replacement;
      try {
        if (Platform.isWindows) {
          await expectLater(
            CartridgeSave.open(dir, rom, ram, rtc),
            throwsA(isA<FileSystemException>()),
          );
        }
        ram[0] = 1;
        await s.checkpoint();
        replacement = await s.file.readAsBytes();
        replacement.last ^= 1;
        await s.file.writeAsBytes(replacement);
        ram[0]++;
        await s.checkpoint();
      } finally {
        await s.close();
      }
      expect(await s.file.readAsBytes(), replacement);
    },
  );
}
