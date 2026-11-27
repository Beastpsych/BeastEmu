import 'dart:typed_data';
import 'dart:io';

import '../../tool/gba_demo.dart';

// Original ARM7TDMI cartridge. On boot it reads its own progress and paints
// the backdrop green on a match. A on a fresh (red) screen writes the marker.
// Only the emulated CPU accesses the cartridge bus, never the host test.
class _Arm {
  _Arm(this.rom) : words = ByteData.sublistView(rom);
  final Uint8List rom;
  final ByteData words;
  int pc = 0xc0;
  final labels = <String, int>{};
  final branches = <int, (String, int)>{};
  void emit(int op) {
    words.setUint32(pc, op, Endian.little);
    pc += 4;
  }

  void label(String name) => labels[name] = pc;
  void branch(String name, [int cond = 14]) {
    branches[pc] = (name, cond);
    emit(0);
  }

  void finish() {
    for (final e in branches.entries) {
      final (label, cond) = e.value;
      final offset = (labels[label]! - e.key - 8) ~/ 4;
      words.setUint32(
        e.key,
        (cond << 28) | 0x0a000000 | (offset & 0xffffff),
        Endian.little,
      );
    }
    if (pc >= 0x3000) throw StateError('Programa excede a área de código.');
  }

  void literal(int reg, int value) {
    emit(0xe59f0000 | (reg << 12)); // ldr reg,[pc]
    emit(0xea000000); // skip the inline literal
    emit(value);
  }

  void store(int addr, int value, int op) {
    literal(0, addr);
    literal(1, value);
    emit(op);
  }

  void byte(int addr, int value) => store(addr, value, 0xe5c01000);
  void half(int addr, int value) => store(addr, value, 0xe1c010b0);
  void word(int addr, int value) => store(addr, value, 0xe5801000);
  void verify(int addr, int value) {
    literal(0, addr);
    emit(0xe5d01000); // ldrb r1,[r0]
    emit(0xe3510000 | value);
    branch('empty', 1);
  }

  void dma(int src, int dest, int control) {
    word(0x040000d4, src);
    word(0x040000d8, dest);
    half(0x040000dc, control & 65535);
    half(0x040000de, control >> 16);
    // DMA3 in immediate mode stalls the CPU until the transfer completes.
    emit(0xe1a00000);
    emit(0xe1a00000);
  }
}

const gbaProgress = [0x5a, 0xd3, 0x18, 0x70, 0x2f, 0x84, 0xc1, 0x39];

Uint8List gbaSaveRom(int size, {int variant = 0}) {
  // Larger than EWRAM so mGBA loads this as a cartridge, not multiboot.
  final rom = Uint8List(512 * 1024)..setAll(0, gbaDemo());
  rom.fillRange(0xc0, rom.length, 0);
  rom[0xbe] = variant;
  final cpu = _Arm(rom);
  const bus = 0x0e000000, eeprom = 0x0d000000;
  final flash = size >= 65536;
  final serial = size <= 8192;
  final address = size == 8192 ? 0x155 : 0x12;
  final bits = size == 8192 ? 14 : 6;
  List<int> msb(int n, int width) => [
    for (var i = width - 1; i >= 0; i--) (n >> i) & 1,
  ];
  final dataBits = [for (final byte in gbaProgress) ...msb(byte, 8)];
  final read = [1, 1, ...msb(address, bits), 0];
  final write = [1, 0, ...msb(address, bits), ...dataBits, 0];
  void table(int addr, List<int> data) {
    for (var i = 0; i < data.length; i++) {
      cpu.words.setUint16(addr + 2 * i, data[i], Endian.little);
    }
  }

  table(0x3000, read);
  table(0x3100, write);
  if (serial) {
    // EEPROM commands originate in work RAM, as on a physical cartridge.
    cpu.literal(0, 0x08003000);
    cpu.literal(1, 0x02001000);
    cpu.literal(2, 128);
    cpu.label('copy');
    cpu.emit(0xe4903004);
    cpu.emit(0xe4813004);
    cpu.emit(0xe2522001);
    cpu.branch('copy', 1);
  }
  void command(int v) {
    cpu.byte(bus + 0x5555, 0xaa);
    cpu.byte(bus + 0x2aaa, 0x55);
    cpu.byte(bus + 0x5555, v);
  }

  void bank(int n) {
    command(0xb0);
    cpu.byte(bus, n);
  }

  cpu.half(0x04000000, 0); // mode 0, backdrop only
  if (flash) {
    command(0x90);
    command(0xf0);
  }
  cpu.label('check');
  if (serial) {
    cpu.dma(0x02001000, eeprom, 0x80400000 | read.length);
    cpu.dma(eeprom, 0x02000000, 0x81000000 | 68);
    cpu.literal(0, 0x02000008); // discard four dummy halfwords
    for (final bit in dataBits) {
      cpu.emit(0xe0d010b2); // ldrh r1,[r0],#2
      cpu.emit(0xe3510000 | bit);
      cpu.branch('empty', 1);
    }
  } else {
    if (size == 131072) bank(0);
    for (var i = 0; i < gbaProgress.length; i++) {
      if (size == 131072 && i == 4) bank(1);
      cpu.verify(bus + 0x234 + i, gbaProgress[i]);
    }
  }
  cpu.half(0x05000000, 0x03e0);
  cpu.label('done');
  cpu.branch('done');
  cpu.label('empty');
  cpu.half(0x05000000, 0x001f);
  cpu.literal(0, 0x04000130); // active-low A
  cpu.label('wait');
  cpu.emit(0xe1d010b0);
  cpu.emit(0xe3110001);
  cpu.branch('wait', 1);
  if (serial) {
    cpu.dma(0x02001100, eeprom, 0x80400000 | write.length);
  } else {
    if (size == 131072) bank(0);
    for (var i = 0; i < gbaProgress.length; i++) {
      if (size == 131072 && i == 4) bank(1);
      if (flash) command(0xa0);
      cpu.byte(bus + 0x234 + i, gbaProgress[i]);
    }
  }
  // Wait out Flash programming/EEPROM settling before reading back.
  cpu.literal(2, 20000);
  cpu.label('settle');
  cpu.emit(0xe2522001);
  cpu.branch('settle', 1);
  cpu.branch('check');
  cpu.finish();
  return rom;
}

Future<void> main(List<String> args) async {
  final size = int.parse(args.first);
  if (!{512, 8192, 32768, 65536, 131072}.contains(size)) {
    throw ArgumentError('Tamanho inválido.');
  }
  final file = File(args[1]);
  await file.create(exclusive: true);
  await file.writeAsBytes(gbaSaveRom(size));
}
