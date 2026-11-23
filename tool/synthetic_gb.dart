import 'dart:typed_data';

/// Builds a 32 KiB SameBoy test cartridge with a header checksum.
Uint8List syntheticHeader({
  required bool color,
  required int mapper,
  String title = '',
}) {
  final rom = Uint8List(32768);
  rom.setAll(0x100, [0, 0xc3, 0x50, 1]);
  // Leave the cartridge logo field (0x104..0x133) blank in test fixtures.
  rom.setAll(0x134, title.codeUnits);
  rom[0x143] = color ? 0xc0 : 0;
  rom[0x147] = mapper;
  rom[0x149] = 3;
  for (var i = 0x134; i <= 0x14c; i++) {
    rom[0x14d] -= rom[i] + 1;
  }
  return rom;
}
