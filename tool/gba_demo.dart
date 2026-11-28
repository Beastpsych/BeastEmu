import 'dart:io';
import 'dart:typed_data';

/// Original ARM homebrew (MIT). Each of the ten horizontal bands turns green
/// while the corresponding active-low KEYINPUT bit is pressed.
Uint8List gbaDemo() {
  final rom = Uint8List(32 * 1024);
  final out = ByteData.sublistView(rom);
  out.setUint32(0, 0xea00002e, Endian.little); // b 0x080000c0
  rom.setAll(0xa0, 'BEAST INPUT'.codeUnits);
  rom[0xb2] = 0x96;
  rom[0xbd] =
      (-0x19 - rom.getRange(0xa0, 0xbd).fold<int>(0, (a, b) => a + b)) & 255;
  final program = [
    0xe3a00301, // mov r0, #0x04000000 (I/O)
    0xe3a01c04, // mov r1, #0x400
    0xe2811003, // add r1, r1, #3 (mode 3, BG2)
    0xe1c010b0, // strh r1, [r0]
    // Enable PSG square 1 on both channels at low volume. The test tone
    // uses only synthesized register writes, with no external audio data.
    0xe3a01080, // mov r1, #0x80
    0xe1c018b4, // strh r1, [r0, #0x84] (master enable)
    0xe3a01c11, // mov r1, #0x1100
    0xe2811077, // add r1, r1, #0x77
    0xe1c018b0, // strh r1, [r0, #0x80] (route square 1 left/right)
    0xe3a01002, // mov r1, #2
    0xe1c018b2, // strh r1, [r0, #0x82] (PSG mix)
    0xe3a01901, // mov r1, #0x4000
    0xe2811080, // add r1, r1, #0x80 (volume 4, duty 50%)
    0xe1c016b2, // strh r1, [r0, #0x62]
    0xe3a01b21, // mov r1, #0x8400 (trigger square 1)
    0xe1c016b4, // strh r1, [r0, #0x64]
    0xe2800e13, // add r0, r0, #0x130 (KEYINPUT)
    0xe1d010b0, // frame: ldrh r1, [r0]
    0xe3a02406, // mov r2, #0x06000000 (VRAM)
    0xe3a03001, // mov r3, #1 (first key)
    0xe1110003, // band: tst r1, r3
    0xe3a05010, // mov r5, #16 (dark red)
    0x03a05e3e, // moveq r5, #0x3e0 (bright green)
    0xe3a04c0f, // mov r4, #3840 (16 rows)
    0xe0c250b2, // pixel: strh r5, [r2], #2
    0xe2544001, // subs r4, r4, #1
    0x1afffffc, // bne pixel
    0xe1a03083, // lsl r3, r3, #1
    0xe3530b01, // cmp r3, #1024
    0x1afffff5, // bne band
    0xeafffff1, // b frame
  ];
  for (var i = 0; i < program.length; i++) {
    out.setUint32(0xc0 + 4 * i, program[i], Endian.little);
  }
  return rom;
}

Future<void> main(List<String> args) async {
  if (args.length != 1 || !args.single.toLowerCase().endsWith('.gba')) {
    throw ArgumentError('Uso: dart run tool/gba_demo.dart <novo-arquivo.gba>');
  }
  final file = File(args.single);
  await file.create(exclusive: true);
  await file.writeAsBytes(gbaDemo(), flush: true);
}
