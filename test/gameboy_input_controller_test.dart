import 'package:beastemu/services/gameboy_input_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Q/E e LB/RB compõem os bits L/R só no GBA', () {
    final gba = GameBoyInputController(gba: true);
    final gb = GameBoyInputController();
    addTearDown(gba.dispose);
    addTearDown(gb.dispose);
    gba.keyDown(LogicalKeyboardKey.keyQ);
    gba.keyDown(LogicalKeyboardKey.keyE);
    gba.setDeviceButtons({GameBoyButton.a}, shoulders: 1 << 10);
    expect(gba.joypadMask, (1 << 10) | (1 << 11) | (1 << 8));
    gba.keyUp(LogicalKeyboardKey.keyQ);
    expect(gba.libretroState(10), 1);
    gba.setDeviceButtons({});
    expect(gba.joypadMask, 1 << 11);
    gba.reset();
    expect(gba.joypadMask, 0);
    gb.keyDown(LogicalKeyboardKey.keyQ);
    gb.setDeviceButtons({}, shoulders: 1 << 11);
    expect(gb.joypadMask, 0);
  });
  late GameBoyInputController input;

  setUp(() => input = GameBoyInputController());
  tearDown(() => input.dispose());

  test('setas e WASD controlam direcoes', () {
    input.keyDown(LogicalKeyboardKey.arrowUp);
    input.keyDown(LogicalKeyboardKey.keyD);
    expect(input.isPressed(GameBoyButton.up), isTrue);
    expect(input.isPressed(GameBoyButton.right), isTrue);
    expect(input.libretroState(4), 1); // UP
    expect(input.libretroState(7), 1); // RIGHT
    input.keyUp(LogicalKeyboardKey.arrowUp);
    expect(input.libretroState(4), 0);
  });

  test('X=A, Z=B, Enter=Start e Shift=Select', () {
    input.keyDown(LogicalKeyboardKey.keyX);
    input.keyDown(LogicalKeyboardKey.keyZ);
    input.keyDown(LogicalKeyboardKey.enter);
    input.keyDown(LogicalKeyboardKey.shiftLeft);
    expect(input.libretroState(8), 1); // A
    expect(input.libretroState(0), 1); // B
    expect(input.libretroState(3), 1); // START
    expect(input.libretroState(2), 1); // SELECT
    expect(input.libretroState(99), 0);
  });

  test('soltar uma tecla nao solta outra com a mesma funcao', () {
    input.keyDown(LogicalKeyboardKey.arrowUp);
    input.keyDown(LogicalKeyboardKey.keyW);
    input.keyUp(LogicalKeyboardKey.arrowUp);
    expect(input.isPressed(GameBoyButton.up), isTrue);
    input.keyUp(LogicalKeyboardKey.keyW);
    expect(input.isPressed(GameBoyButton.up), isFalse);
  });

  test('reset limpa todos os comandos', () {
    input.keyDown(LogicalKeyboardKey.keyX);
    input.keyDown(LogicalKeyboardKey.arrowLeft);
    input.reset();
    expect(input.pressedButtons, isEmpty);
    expect(input.libretroState(8), 0);
  });

  test('ignora teclas que nao pertencem ao Game Boy', () {
    input.keyDown(LogicalKeyboardKey.keyP);
    expect(input.pressedButtons, isEmpty);
  });
}
