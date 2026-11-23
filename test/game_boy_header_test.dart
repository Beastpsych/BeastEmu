import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:beastemu/services/game_boy_header.dart';

Uint8List romHeader(String title, int flag) {
  final data = Uint8List(0x150);
  final limit = (flag == 0x80 || flag == 0xC0) ? 15 : 16;
  for (var i = 0; i < title.length && i < limit; i++) {
    data[0x134 + i] = title.codeUnitAt(i);
  }
  data[0x143] = flag;
  return data;
}

void main() {
  test('Lê nome de cartucho clássico', () {
    final rom = romHeader('POKEMON BLUE', 0x00);
    final game = GameBoyHeaderReader.fromBytes(rom);
    expect(game.title, 'POKEMON BLUE');
    expect(game.libraryConsole, 'Game Boy');
  });

  test('Distingue GBC compatível com GB', () {
    final game = GameBoyHeaderReader.fromBytes(romHeader('TEST COLOR', 0x80));
    expect(game.libraryConsole, 'GB / GBC');
  });

  test('Distingue GBC exclusivo', () {
    final game = GameBoyHeaderReader.fromBytes(romHeader('COLOR ONLY', 0xC0));
    expect(game.libraryConsole, 'Game Boy Color');
  });

  test('Rejeita arquivo menor que o cabeçalho', () {
    expect(
      () => GameBoyHeaderReader.fromBytes(Uint8List(15)),
      throwsFormatException,
    );
  });
}
