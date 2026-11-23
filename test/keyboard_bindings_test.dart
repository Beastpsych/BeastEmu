import 'dart:io';

import 'package:beastemu/services/gameboy_input_controller.dart';
import 'package:beastemu/services/keyboard_bindings.dart' show EmulatorShortcut;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late KeyboardBindings bindings;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('beastemu-keyboard-');
    bindings = KeyboardBindings(directory: directory);
  });
  tearDown(() async {
    bindings.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'atalho da aceleração persiste sem ocupar uma tecla do cartucho',
    () async {
      expect(
        bindings.shortcutKey(EmulatorShortcut.holdSpeed),
        LogicalKeyboardKey.tab,
      );
      await expectLater(
        bindings.bindShortcut(
          EmulatorShortcut.holdSpeed,
          LogicalKeyboardKey.keyW,
        ),
        throwsArgumentError,
      );
      await expectLater(
        bindings.bindShortcut(
          EmulatorShortcut.holdSpeed,
          LogicalKeyboardKey.f11,
        ),
        throwsArgumentError,
      );
      await bindings.bindShortcut(
        EmulatorShortcut.holdSpeed,
        LogicalKeyboardKey.keyP,
      );
      await bindings.bind(GameBoyButton.a, LogicalKeyboardKey.space);
      await expectLater(
        bindings.bind(GameBoyButton.b, LogicalKeyboardKey.keyP),
        throwsArgumentError,
      );
      final fresh = KeyboardBindings(directory: directory);
      addTearDown(fresh.dispose);
      await fresh.load();
      expect(
        fresh.shortcutKey(EmulatorShortcut.holdSpeed),
        LogicalKeyboardKey.keyP,
      );
      expect(fresh.buttonFor(LogicalKeyboardKey.space), GameBoyButton.a);
      await fresh.restoreShortcuts();
      expect(
        fresh.shortcutKey(EmulatorShortcut.holdSpeed),
        LogicalKeyboardKey.tab,
      );
    },
  );

  test(
    'seis atalhos persistem e restaurar preserva teclas do cartucho',
    () async {
      final keys = [
        LogicalKeyboardKey.f1,
        LogicalKeyboardKey.f2,
        LogicalKeyboardKey.f3,
        LogicalKeyboardKey.f4,
        LogicalKeyboardKey.f6,
        LogicalKeyboardKey.f7,
      ];
      await bindings.bind(GameBoyButton.b, LogicalKeyboardKey.keyJ);
      for (final action in EmulatorShortcut.values) {
        expect(bindings.actionFor(action.defaultKey), action);
        await bindings.bindShortcut(action, keys[action.index]);
      }
      await expectLater(
        bindings.bindShortcut(EmulatorShortcut.mute, keys.first),
        throwsArgumentError,
      );
      final fresh = KeyboardBindings(directory: directory);
      addTearDown(fresh.dispose);
      await fresh.load();
      for (final action in EmulatorShortcut.values) {
        expect(fresh.actionFor(keys[action.index]), action);
      }
      await fresh.restoreShortcuts();
      expect(fresh.buttonFor(LogicalKeyboardKey.keyJ), GameBoyButton.b);
      for (final action in EmulatorShortcut.values) {
        expect(fresh.actionFor(action.defaultKey), action);
      }
    },
  );

  test('atalhos antigos e teclas do jogo têm prioridade sobre novos padrões', () async {
    await File('${directory.path}/keyboard-bindings-v1.json').writeAsString(
      '{"b":${LogicalKeyboardKey.keyM.keyId},"fastForward":${LogicalKeyboardKey.f8.keyId}}',
    );
    await bindings.load();
    expect(
      bindings.actionFor(LogicalKeyboardKey.f8),
      EmulatorShortcut.holdSpeed,
    );
    expect(bindings.shortcutKey(EmulatorShortcut.cycleSpeed), isNull);
    expect(bindings.buttonFor(LogicalKeyboardKey.keyM), GameBoyButton.b);
    expect(bindings.shortcutKey(EmulatorShortcut.mute), isNull);
  });

  test(
    'recusa duplicatas e teclas reservadas sem remover os padrões',
    () async {
      for (final key in [
        LogicalKeyboardKey.f11,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.tab,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.metaRight,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.arrowUp,
      ]) {
        await expectLater(
          bindings.bind(GameBoyButton.a, key),
          throwsArgumentError,
        );
      }
      expect(bindings.keysFor(GameBoyButton.a), [LogicalKeyboardKey.keyX]);
    },
  );

  test(
    'aplica e persiste remapeamentos rápidos e restaura todos os aliases',
    () async {
      final input = GameBoyInputController(bindings: bindings);
      addTearDown(input.dispose);
      input.keyDown(LogicalKeyboardKey.arrowUp);
      await Future.wait([
        bindings.bind(GameBoyButton.up, LogicalKeyboardKey.keyI),
        bindings.bind(GameBoyButton.a, LogicalKeyboardKey.keyW),
      ]);
      expect(input.libretroState(4), 0);
      input.keyDown(LogicalKeyboardKey.keyW);
      expect(input.libretroState(8), 1);
      final fresh = KeyboardBindings(directory: directory);
      addTearDown(fresh.dispose);
      await fresh.load();
      expect(fresh.buttonFor(LogicalKeyboardKey.keyI), GameBoyButton.up);
      expect(fresh.buttonFor(LogicalKeyboardKey.keyW), GameBoyButton.a);
      expect(fresh.buttonFor(LogicalKeyboardKey.arrowUp), isNull);
      await fresh.restoreDefaults();
      final restored = KeyboardBindings(directory: directory);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.keysFor(GameBoyButton.up), [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.keyW,
      ]);
      expect(restored.keysFor(GameBoyButton.select), [
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.shiftRight,
      ]);
    },
  );

  test('descarta configuração duplicada e preserva o teclado e outros dispositivos', () async {
    await File('${directory.path}/keyboard-bindings-v1.json')
        .writeAsString('{"b":${LogicalKeyboardKey.keyX.keyId}}');
    await bindings.load();
    expect(bindings.storageMessage, isNotNull);
    final input = GameBoyInputController(bindings: bindings);
    addTearDown(input.dispose);
    input.setDeviceButtons({GameBoyButton.a, GameBoyButton.start});
    input.keyDown(LogicalKeyboardKey.keyX);
    input.setDeviceButtons({});
    expect(input.libretroState(8), 1);
    expect(input.libretroState(3), 0);
    input.reset();
    expect(input.pressedButtons, isEmpty);
  });
}
