import 'dart:async';
import 'dart:io';

import 'package:beastemu/services/gameboy_input_controller.dart';
import 'package:beastemu/services/gamepads.dart';
import 'package:beastemu/services/xinput.dart';
import 'package:beastemu/services/sameboy_live_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sameboy_cartridge_integration_test.dart' show cartridge;

// This ROM has no battery or cartridge RAM. It changes the entire DMG
// background palette when A is held, making the core's input visible in RGBA.
Uint8List joypadCartridge() {
  final rom = cartridge(false);
  rom[0x147] = 0;
  rom[0x149] = 0;
  rom[0x14d] = 0;
  for (var offset = 0x134; offset <= 0x14c; offset++) {
    rom[0x14d] -= rom[offset] + 1;
  }
  rom.setAll(0x150, [
    0x3e, 0x10, 0xe0, 0x00, // Select the four action buttons in JOYP.
    0xf0, 0x00, 0xe6, 0x01, // A = JOYP bit 0 (0 means pressed).
    0x3e, 0xff, 0x28, 0x01, // When pressed, choose the darkest shade.
    0xaf, // Otherwise choose the brightest shade.
    0xe0, 0x47, // Write all four mappings in BGP.
    0x18, 0xf3, // Poll JOYP again.
  ]);
  return rom;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'encerrar durante a abertura libera a sessão uma única vez',
    () async {
      final dir = await Directory.systemTemp.createTemp('beast-start-stop-');
      try {
        final file = File('${dir.path}/no-battery.gb');
        await file.writeAsBytes(joypadCartridge());
        final session = SameBoyLiveService();
        final startup = session.start(
          romPath: file.path,
          onFrame: (_) => fail('A abertura foi cancelada.'),
          onError: fail,
        );
        final shutdown = session.stop();
        expect(identical(session.stop(), shutdown), isTrue);
        await Future.wait([startup, shutdown])
            .timeout(const Duration(seconds: 5));
      } finally {
        await dir.delete(recursive: true);
      }
    },
    skip:
        !Platform.isWindows ||
        !File('cores/windows/sameboy_libretro.dll').existsSync(),
  );
  test(
    'a DLL recebe o mesmo A pelo teclado e pelo XInput simulado',
    () async {
      final dir = await Directory.systemTemp.createTemp('beast-joypad-');
      final file = File('${dir.path}/joypad.gb');
      final bindings = KeyboardBindings(directory: dir);
      final restored = KeyboardBindings(directory: dir);
      final input = GameBoyInputController(bindings: restored);
      final samples = StreamController<List<int?>>.broadcast(sync: true);
      final pads = Gamepads(watch: () => samples.stream);
      pads.addListener(
        () => input.setDeviceButtons(pads.buttonsFor(PadPlayer.one)),
      );
      final session = SameBoyLiveService();
      try {
        await file.writeAsBytes(joypadCartridge());
        await bindings.bind(GameBoyButton.a, LogicalKeyboardKey.keyP);
        await restored.load();
        input.addListener(() => session.sendMask(input.joypadMask));

        var frames = 0;
        var pressed = false;
        var released = false;
        var padPressed = false;
        var disconnected = false;
        var initialBrightness = 0;
        final done = Completer<void>();
        await Future.wait([
          session.start(
            romPath: file.path,
            volume: 0,
            onFrame: (pixels) {
              // Allow the built-in boot ROM to hand off to the test program.
              if (++frames < 150 || done.isCompleted) return;
              final brightness = pixels[0] + pixels[1] + pixels[2];
              if (!pressed) {
                initialBrightness = brightness;
                pressed = true;
                input.handleKeyEvent(
                  const KeyDownEvent(
                    physicalKey: PhysicalKeyboardKey.keyP,
                    logicalKey: LogicalKeyboardKey.keyP,
                    timeStamp: Duration.zero,
                  ),
                );
              } else if (!released && brightness < initialBrightness - 128) {
                released = true;
                input.handleKeyEvent(
                  const KeyUpEvent(
                    physicalKey: PhysicalKeyboardKey.keyP,
                    logicalKey: LogicalKeyboardKey.keyP,
                    timeStamp: Duration.zero,
                  ),
                );
              } else if (released &&
                  !padPressed &&
                  brightness == initialBrightness) {
                padPressed = true;
                samples.add([PadControl.a.bit, null, null, null]);
              } else if (padPressed &&
                  !disconnected &&
                  brightness < initialBrightness - 128) {
                disconnected = true;
                samples.add([null, null, null, null]);
              } else if (disconnected && brightness == initialBrightness) {
                done.complete();
              }
            },
            onError: (error) {
              if (!done.isCompleted) done.completeError(StateError(error));
            },
          ),
          done.future.timeout(const Duration(seconds: 35)),
        ], eagerError: true);
      } finally {
        await session.stop();
        pads.dispose();
        await samples.close();
        input.dispose();
        restored.dispose();
        bindings.dispose();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 1)),
    skip:
        !Platform.isWindows ||
        !File('cores/windows/sameboy_libretro.dll').existsSync(),
  );
}
