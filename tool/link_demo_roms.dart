import 'dart:io';
import 'dart:typed_data';

import 'synthetic_gb.dart';

// The ROM only learns the peer's byte by reading SB after SC clears bit 7.
// A selects internal clock, B arms the external clock. Both roles live in
// each cartridge so the exact same file can occupy both slots.
Uint8List serialCartridge({
  required bool color,
  required int masterByte,
  required int slaveByte,
}) {
  final rom = syntheticHeader(
    color: color,
    mapper: 0x10,
    title: color ? 'LINK RIGHT' : 'LINK LEFT',
  );
  final code = <int>[];
  int getPC() => 0x150 + code.length;
  void loadA(int n) => code.addAll([0x3e, n]);
  void write(int address) => code.addAll([0xea, address & 255, address >> 8]);
  void read(int address) => code.addAll([0xfa, address & 255, address >> 8]);
  void store(int address, int value) {
    loadA(value);
    write(address);
  }

  void shade(int dmg, int rgb) {
    // CGB palette RAM is writable during VBlank on both sides of the link.
    final wait = getPC();
    read(0xff44);
    code.addAll([0xfe, 144, 0xc2, wait & 255, wait >> 8]);
    store(0xff47, dmg);
    store(0xff68, 0x80);
    store(0xff69, rgb & 255);
    store(0xff69, rgb >> 8);
  }

  code.add(0xf3); // DI
  store(0, 10); // enable SRAM and RTC
  read(0xa000);
  write(0xa005); // previous session's received byte
  store(0x6000, 0);
  store(0x6000, 1);
  store(0x4000, 8);
  read(0xa000);
  code.add(0x47); // latched seconds -> B
  store(0x4000, 0);
  code.add(0x78);
  write(0xa006);
  shade(0, 0x7fff);
  store(0xff00, 0x10);
  final poll = getPC();
  read(0xff00);
  code.addAll([0xcb, 0x47, 0x28, 0]); // BIT 0,A / JR Z,master
  final masterJump = code.length - 1;
  code.addAll([
    0xcb,
    0x4f,
    0xc2,
    poll & 255,
    poll >> 8,
  ]); // BIT 1,A / JP NZ,poll
  void transfer(int byte, bool master) {
    store(0x4000, 8);
    store(0xa000, master ? 12 : 42);
    store(0x4000, 0);
    store(0xa001, master ? 1 : 2);
    store(0xff01, byte);
    store(0xff02, master ? 0x81 : 0x80);
    if (!master) shade(0x55, 0x5294);
    final wait = getPC();
    read(0xff02);
    code.addAll([0xcb, 0x7f, 0xc2, wait & 255, wait >> 8]);
    read(0xff01);
    write(0xa000);
    code.addAll([
      0xfe,
      0xff,
      0x28,
      0xfe,
    ]); // No peer: stay at the waiting shade.
    shade(master ? 0xff : 0xaa, master ? 0 : 0x294a);
    code.addAll([0x18, 0xfe]);
  }

  transfer(slaveByte, false);
  code[masterJump] = code.length - masterJump - 1;
  if (code[masterJump] > 127) {
    throw StateError('Salto fora do alcance da ROM de teste');
  }
  transfer(masterByte, true);
  rom.setAll(0x150, code);
  return rom;
}

Future<void> main() async {
  final parent = await Directory('build/link-demo').create(recursive: true);
  final folder = await parent.createTemp('serial-');
  await File('${folder.path}/Link Left.gb').writeAsBytes(
    serialCartridge(color: false, masterByte: 0xa6, slaveByte: 0x37),
  );
  await File('${folder.path}/Link Right.gbc').writeAsBytes(
    serialCartridge(color: true, masterByte: 0x83, slaveByte: 0x59),
  );
  stdout.writeln(folder.absolute.path);
}
