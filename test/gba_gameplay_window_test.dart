import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:beastemu/services/emulation_settings.dart';
import 'package:beastemu/services/keyboard_bindings.dart';
import 'package:beastemu/services/sameboy_live_service.dart';
import 'package:beastemu/widgets/sameboy_live_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/gba_demo.dart';

// Widget tests advance a virtual clock. Keep sockets, process exit and the
// real core on wall-clock time while Flutter controls its own frame pumps.
class _WindowsSession extends SameBoyLiveService {
  _WindowsSession(this.io);
  final Zone io;

  @override
  Future<void> start({
    required String romPath,
    int volume = 100,
    required void Function(Uint8List) onFrame,
    required void Function(String) onError,
  }) => io.run(
    () => super.start(
      romPath: romPath,
      volume: volume,
      onFrame: onFrame,
      onError: onError,
    ),
  );

  @override
  Future<void> stop() => io.run(super.stop);
}

void main() {
  testWidgets('Janela decodifica vídeo real e transmite Q ao cartucho GBA', (
    tester,
  ) async {
    final io = (await tester.runAsync(() async => Zone.current))!;
    final dir = Directory.systemTemp.createTempSync('beast-gba-window-');
    final rom = File('${dir.path}/demo.gba')..writeAsBytesSync(gbaDemo());
    final session = _WindowsSession(io);
    addTearDown(() async {
      await session.stop();
      dir.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SameBoyLiveDialog(
                romPath: rom.path,
                gameTitle: 'BEAST INPUT',
                service: session,
                bindings: KeyboardBindings(directory: dir),
                settings: EmulationSettings(directory: dir),
              ),
            ),
            child: const Text('Abrir demonstração'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir demonstração'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    Future<void> expectShoulder({required bool pressed}) async {
      final clock = Stopwatch()..start();
      while (clock.elapsed < const Duration(seconds: 20)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump();
        final raw = tester
            .widgetList<RawImage>(find.byType(RawImage))
            .firstOrNull;
        if (raw?.image == null) continue;
        final image = raw!.image!.clone();
        try {
          expect((image.width, image.height), (240, 160));
          final data = await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
          );
          final pixel = (152 * image.width + 120) * 4; // Center of the L band.
          if (data != null &&
              (pressed
                  ? data.getUint8(pixel + 1) > 200 && data.getUint8(pixel) < 32
                  : data.getUint8(pixel) > 100 &&
                        data.getUint8(pixel + 1) < 50)) {
            return;
          }
        } finally {
          image.dispose();
        }
      }
      fail(
        'A faixa de L na imagem do Flutter não chegou ao estado pressionado=$pressed.',
      );
    }

    await expectShoulder(pressed: false);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);
    await expectShoulder(pressed: true);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
    await expectShoulder(pressed: false);
    await tester.tap(find.text('Sair'));
    await tester.runAsync(session.stop);
    await tester.pumpAndSettle();
    expect(find.byType(SameBoyLiveDialog), findsNothing);
  }, skip: !Platform.isWindows);
}
