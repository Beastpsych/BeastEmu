import 'dart:async';
import 'dart:io';

import 'package:beastemu/services/gamepads.dart';
import 'package:beastemu/services/keyboard_bindings.dart';
import 'package:beastemu/services/xinput.dart';
import 'package:beastemu/widgets/gamepad_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Preferences extends Fake implements SharedPreferencesAsync {
  final data = <String, Object>{};

  @override
  Future<List<String>?> getStringList(String key) async =>
      data[key] as List<String>?;

  @override
  Future<void> setStringList(String key, List<String> value) async {
    data[key] = List.of(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Preferences preferences;
  setUp(() => preferences = _Preferences());

  test(
    'XInput consulta os quatro slots do Windows e permite reabrir a leitura',
    () async {
      for (var i = 0; i < 2; i++) {
        final slots = await watchXInput().first.timeout(
          const Duration(seconds: 8),
        );
        expect(slots.length, 4);
      }
    },
    skip: !Platform.isWindows,
  );

  test('deadzone por eixo, diagonais, gatilhos e bits reservados', () {
    expect(xinputMask(0x0c00, 7849, -7849, 30, 30), 0);
    expect(
      xinputMask(0x1000, -7850, 7850, 31, 31),
      PadControl.a.bit |
          PadControl.stickLeft.bit |
          PadControl.stickUp.bit |
          PadControl.lt.bit |
          PadControl.rt.bit,
    );
    expect(
      xinputMask(1, 32767, -32768, 0, 0),
      PadControl.up.bit | PadControl.stickRight.bit | PadControl.stickDown.bit,
    );
  });

  test(
    'cada jogador recebe seu próprio controle e as oito associações lógicas',
    () async {
      final events = StreamController<List<int?>>.broadcast(sync: true);
      final pads = Gamepads(watch: () => events.stream);
      pads.addListener(() {});
      for (final button in GameBoyButton.values) {
        events.add([null, pads.binding(button).bit, null, PadControl.y.bit]);
        expect(pads.buttonsFor(PadPlayer.one), {button});
        expect(pads.buttonsFor(PadPlayer.two), isEmpty);
      }
      events.add([null, PadControl.stickDown.bit, null, PadControl.start.bit]);
      expect(pads.buttonsFor(PadPlayer.one), {GameBoyButton.down});
      expect(pads.buttonsFor(PadPlayer.two), {GameBoyButton.start});
      events.add([null, null, null, 0]);
      expect(pads.slotFor(PadPlayer.one), 3);
      expect(pads.slotFor(PadPlayer.two), isNull);
      pads.dispose();
      expect(events.hasListener, isFalse);
      await events.close();
    },
  );

  test(
    'remapeamentos simultâneos, troca e restauração sobrevivem à reabertura',
    () async {
      final pads = Gamepads(preferences: preferences);
      final reopened = Gamepads(preferences: preferences);
      final defaults = Gamepads(preferences: preferences);
      preferences.data['beastemu.gameboy.library.v1'] = 'catálogo importado';
      await Future.wait([
        pads.bind(GameBoyButton.a, PadControl.b),
        pads.bind(GameBoyButton.start, PadControl.rt),
      ]);
      await reopened.load();
      expect(reopened.binding(GameBoyButton.a), PadControl.b);
      expect(reopened.binding(GameBoyButton.b), PadControl.a);
      expect(reopened.binding(GameBoyButton.start), PadControl.rt);
      expect(
        preferences.data['flutter.xinput-bindings-v1'],
        isA<List<String>>(),
      );
      expect(
        preferences.data['beastemu.gameboy.library.v1'],
        'catálogo importado',
      );
      await reopened.restore();
      await defaults.load();
      expect(defaults.binding(GameBoyButton.a), PadControl.a);
      expect(defaults.binding(GameBoyButton.start), PadControl.start);
      for (final p in [pads, reopened, defaults]) {
        p.dispose();
      }
    },
  );

  testWidgets(
    'painel mostra conexão, botões físicos, remapeamento e desconexão',
    (tester) async {
      final events = StreamController<List<int?>>.broadcast(sync: true);
      final pads = Gamepads(
        watch: () => events.stream,
        preferences: preferences,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GamepadSettingsPanel(pads: pads),
            ),
          ),
        ),
      );
      expect(find.text('Nenhum controle XInput conectado.'), findsOneWidget);
      events.add([PadControl.b.bit | PadControl.rt.bit, 0, null, null]);
      await tester.pump();
      expect(find.text('B  ·  RT'), findsOneWidget);
      expect(find.textContaining('Jogador 2 (reservado)'), findsOneWidget);
      final edit = find.byTooltip('Mapear controle · A');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      final x = find.widgetWithText(PopupMenuItem<PadControl>, 'X');
      await tester.ensureVisible(x);
      await tester.tap(x);
      await tester.pumpAndSettle();
      expect(pads.binding(GameBoyButton.a), PadControl.x);
      events.add([null, null, null, null]);
      await tester.pump();
      expect(find.text('Nenhum controle XInput conectado.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(events.hasListener, isFalse);
      pads.dispose();
      await events.close();
    },
  );
}
