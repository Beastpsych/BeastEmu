import 'dart:async';
import 'dart:io';

import 'package:beastemu/services/sameboy_commands.dart';
import 'package:beastemu/services/gamepads.dart';
import 'package:beastemu/services/xinput.dart';
import 'package:beastemu/services/emulation_settings.dart';
import 'package:beastemu/services/keyboard_bindings.dart';
import 'package:beastemu/services/sameboy_live_service.dart';
import 'package:beastemu/widgets/sameboy_live_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends SameBoyLiveService {
  final speeds = <int>[];
  final volumes = <int>[];
  @override
  void setVolume(int percent) => volumes.add(percent);
  @override
  void setSpeed(int speed) => speeds.add(speed);
  late void Function(Uint8List) emit;
  final commands = <int>[];
  @override
  Future<List<String?>> stateCommand(int command) async {
    commands.add(command);
    if (command == loadStateBase + 2) cartridgeProtected = true;
    return command == listStateSlots
        ? [
            null,
            commands.contains(createStateBase + 2)
                ? '2026-01-01T10:00:00Z'
                : null,
            null,
            null,
            null,
          ]
        : [];
  }

  int starts = 0;
  int stops = 0;
  bool timeoutOnce = false;
  final masks = <int>[];
  final pairs = <(int, int)>[];
  @override
  void sendLinkMasks(int first, int second) => pairs.add((first, second));

  @override
  Future<void> start({
    required String romPath,
    int volume = 100,
    required void Function(Uint8List) onFrame,
    required void Function(String) onError,
  }) async {
    emit = onFrame;
    starts++;
  }

  @override
  void sendMask(int mask) => masks.add(mask);

  @override
  Future<void> stop() async {
    stops++;
    if (timeoutOnce) {
      timeoutOnce = false;
      throw TimeoutException('Gravação em andamento');
    }
  }
}

const _channel = MethodChannel('beastemu/window');
const _enter = 'Tela cheia (F11)';
const _leave = 'Sair da tela cheia (F11)';

Future<void> _open(
  WidgetTester tester,
  _Session session, {
  Gamepads? pads,
  bool dual = false,
  EmulationSettings? settings,
}) async {
  await tester.binding.setSurfaceSize(const Size(1100, 850));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => SameBoyLiveDialog(
                service: session,
                gamepads: pads,
                settings: settings ?? EmulationSettings(),
                bindings: KeyboardBindings(),
                romPath: 'synthetic.gb',
                partner: dual
                    ? (path: 'synthetic.gbc', title: 'Parceiro')
                    : null,
                gameTitle: 'Cartucho de teste',
              ),
            ),
            child: const Text('Abrir jogo'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir jogo'));
  await _update(tester);
  expect(session.starts, 1);
}

// A loading game continuously animates its progress indicator.
Future<void> _update(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _firstFrame(
  WidgetTester tester,
  _Session session, {
  int width = 160,
}) async {
  session.emit(Uint8List(width * 144 * 4));
  for (
    var attempt = 0;
    attempt < 50 && find.byType(RawImage).evaluate().isEmpty;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(find.byType(RawImage), findsOneWidget);
  await _update(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final requests = <bool>[];
  var failOnce = false;

  setUp(() {
    requests.clear();
    failOnce = false;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'setFullscreen');
      final requested = call.arguments as bool;
      requests.add(requested);
      if (failOnce) {
        failOnce = false;
        throw PlatformException(code: 'window', message: 'Falha simulada');
      }
      return requested;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  testWidgets(
    'Link Cable aguarda nova confirmação do auxiliar após demora na gravação',
    (tester) async {
      final session = _Session()..timeoutOnce = true;
      await _open(tester, session, dual: true);
      await tester.tap(find.text('Sair'));
      await _update(tester);
      expect(find.text('Falha na sessão do SameBoy'), findsOneWidget);
      expect(session.stops, 1);
      await tester.tap(find.text('Sair'));
      await _update(tester);
      expect(session.stops, 2);
      expect(find.text('Abrir jogo'), findsOneWidget);
    },
  );

  testWidgets('Link Cable roteia teclado e um ou dois controles por jogador', (
    tester,
  ) async {
    final events = StreamController<List<int?>>.broadcast(sync: true);
    final pads = Gamepads(watch: () => events.stream);
    final session = _Session();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _open(tester, session, pads: pads, dual: true);
    await _firstFrame(tester, session, width: 320);
    expect(find.textContaining('Jogador 1 ·'), findsOneWidget);
    expect(find.text('Jogador 2 · Parceiro'), findsOneWidget);
    final lcd = tester.getSize(find.byType(RawImage));
    expect(lcd.width / lcd.height, closeTo(320 / 144, .001));
    expect(find.text('Salvar estado'), findsNothing);
    expect(find.text('Carregar estado'), findsNothing);
    expect(find.text('Acelerar'), findsNothing);
    events.add([0, null, null, null]);
    events.add([PadControl.b.bit, null, null, null]);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
    expect(session.pairs.last, (256, 1));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
    events.add([0, 0, null, null]);
    events.add([PadControl.start.bit, PadControl.back.bit, null, null]);
    expect(session.pairs.last, (8, 4));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(session.pairs.last, (0, 0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    for (final key in [
      LogicalKeyboardKey.f5,
      LogicalKeyboardKey.f9,
      LogicalKeyboardKey.f8,
    ]) {
      await tester.sendKeyEvent(key);
    }
    expect(session.commands, isEmpty);
    expect(session.speeds, isEmpty);
    await tester.tap(find.text('Sair'));
    await _update(tester);
    expect(session.stops, 1);
    expect(events.hasListener, isFalse);
    pads.dispose();
    await events.close();
  });

  testWidgets(
    'gamepad e teclado mantêm origens independentes e liberam ao perder foco',
    (tester) async {
      final events = StreamController<List<int?>>.broadcast(sync: true);
      final pads = Gamepads(watch: () => events.stream);
      final session = _Session();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _open(tester, session, pads: pads);
      void sample(int? mask) => events.add([mask, null, null, null]);
      sample(0);
      sample(PadControl.a.bit);
      expect(session.masks.last, 1 << 8);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
      sample(null);
      expect(session.masks.last, 1 << 8);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
      expect(session.masks.last, 0);
      sample(PadControl.a.bit);
      expect(session.masks.last, 0);
      sample(0);
      sample(PadControl.b.bit);
      expect(session.masks.last, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(session.masks.last, 0);
      sample(PadControl.a.bit);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(session.masks.last, 0);
      sample(0);
      sample(PadControl.a.bit);
      expect(session.masks.last, 1 << 8);
      await tester.tap(find.byTooltip('Configurações do jogo'));
      await _update(tester);
      expect(session.masks.last, 0);
      await tester.tap(find.text('Voltar ao jogo'));
      await _update(tester);
      expect(session.masks.last, 0);
      sample(0);
      sample(PadControl.back.bit);
      expect(session.masks.last, 1 << 2);
      await tester.tap(find.text('Sair'));
      await _update(tester);
      expect(session.masks.last, 0);
      expect(events.hasListener, isFalse);
      pads.dispose();
      await events.close();
    },
  );

  testWidgets(
    'salva pela janela e carrega em tela cheia com foco devolvido ao jogo',
    (tester) async {
      final session = _Session();
      await _open(tester, session);
      await _firstFrame(tester, session);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX);
      await tester.tap(find.text('Salvar estado'));
      await _update(tester);
      expect(session.masks.last, 0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
      await tester.tap(find.text('Slot 2'));
      await _update(tester);
      expect(find.text('Estado salvo no slot 2.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await _update(tester);
      await tester.tap(find.text('Carregar estado'));
      await _update(tester);
      await tester.tap(find.text('Slot 2'));
      await _update(tester);
      await tester.tap(find.text('Carregar'));
      await _update(tester);
      expect(find.text('Estado carregado do slot 2.'), findsOneWidget);
      expect(find.textContaining('Cartucho protegido'), findsOneWidget);
      expect(session.commands, [
        listStateSlots,
        createStateBase + 2,
        listStateSlots,
        loadStateBase + 2,
      ]);
      final count = session.masks.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      expect(session.masks.skip(count), [1 << 8, 0]);
      await tester.tap(find.byTooltip('Fechar'));
      await _update(tester);
      expect(session.stops, 1);
    },
  );

  testWidgets('comandos e LCD cabem na janela estreita e em tela cheia', (
    tester,
  ) async {
    final session = _Session();
    await _open(tester, session);
    await tester.binding.setSurfaceSize(const Size(360, 440));
    await _firstFrame(tester, session);
    for (final fullscreen in [false, true]) {
      if (fullscreen) {
        await tester.tap(find.text('Tela cheia'));
        await _update(tester);
      }
      final lcd = tester.getRect(find.byType(RawImage));
      expect(lcd.width / lcd.height, closeTo(160 / 144, .001));
      expect(lcd.height, greaterThan(200));
      for (final label in [
        'Salvar estado',
        'Carregar estado',
        'Acelerar',
        fullscreen ? 'Modo janela' : 'Tela cheia',
        'Sair',
      ]) {
        final text = find.text(label).hitTestable();
        expect(text, findsOneWidget);
        expect(tester.getRect(text).bottom, lessThanOrEqualTo(lcd.top));
      }
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Sair'));
    await _update(tester);
    expect(session.stops, 1);
  });

  testWidgets(
    'seleciona quatro velocidades e restaura a seleção ao soltar a tecla',
    (tester) async {
      final session = _Session();
      await _open(tester, session);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await _update(tester);
      expect(find.text('4×'), findsOneWidget);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      await _update(tester);
      expect(find.text('1×'), findsOneWidget);
      await tester.tap(find.byTooltip('Selecionar 2×'));
      await _update(tester);
      await tester.tap(find.byTooltip('Configurações do jogo'));
      await _update(tester);
      await tester.tap(find.text('Voltar ao jogo'));
      await _update(tester);
      expect(find.text('2×'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await _update(tester);
      expect(find.text('2×'), findsOneWidget);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (final speed in [3, 4, 1]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.f8);
        await _update(tester);
        expect(find.text('$speed×'), findsOneWidget);
      }
      await _update(tester);
      await tester.tap(find.byTooltip('Fechar'));
      await _update(tester);
      expect(session.speeds, [4, 1, 2, 4, 2, 3, 4, 1]);
      expect(session.stops, 1);
    },
  );

  testWidgets('F5 e F9 atuam uma vez e os diálogos não executam atalhos', (
    tester,
  ) async {
    final session = _Session();
    await _open(tester, session);
    await _firstFrame(tester, session);
    for (final key in [LogicalKeyboardKey.f5, LogicalKeyboardKey.f9]) {
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyUpEvent(key);
      await _update(tester);
    }
    expect(session.commands, [quickSave, quickLoad]);
    expect(
      find.text('Estado rápido carregado: Cartucho de teste'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Configurações do jogo'));
    await _update(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    expect(session.commands, [quickSave, quickLoad]);
    await tester.tap(find.text('Voltar ao jogo'));
    await _update(tester);
    await tester.tap(find.text('Sair'));
    await _update(tester);
  });

  testWidgets(
    'M conserva o volume durante a aceleração e depois de voltar a 1×',
    (tester) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('beast-mute-'),
      );
      final settings = EmulationSettings(directory: directory!);
      await tester.runAsync(() => settings.setVolume(36));
      final session = _Session();
      await _open(tester, session, settings: settings);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.runAsync(() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
        await settings.setVolume(36);
      });
      await _update(tester);
      expect(session.volumes.last, 0);
      expect(settings.volume, 36);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      expect(session.speeds, [4, 1]);
      expect(settings.muted, isTrue);
      await tester.runAsync(() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
        await settings.setVolume(36);
      });
      await _update(tester);
      expect(session.volumes.last, 36);
      await tester.tap(find.text('Sair'));
      await _update(tester);
      settings.dispose();
      await tester.runAsync(() => directory.delete(recursive: true));
    },
  );

  testWidgets(
    'F11, botão e Esc preservam a sessão e o fechamento restaura a janela',
    (tester) async {
      final session = _Session();
      await _open(tester, session);
      await tester.tap(find.byTooltip(_enter));
      await _update(tester);
      expect(find.byTooltip(_leave), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _update(tester);
      expect(find.byTooltip(_enter), findsOneWidget);

      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.f11);
        await _update(tester);
      }
      expect(find.byTooltip(_leave), findsOneWidget);
      expect(requests, [true, false, true, false, true]);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      expect(session.masks, contains(1 << 8));
      expect(session.starts, 1);
      expect(session.stops, 0);
      await tester.tap(find.byTooltip('Fechar'));
      await _update(tester);
      expect(find.byType(SameBoyLiveDialog), findsNothing);
      expect(requests.last, isFalse);
      expect(session.stops, 1);
    },
  );

  testWidgets(
    'falha da janela permite repetir a operação e descartar a sessão',
    (tester) async {
      final session = _Session();
      await _open(tester, session);
      failOnce = true;
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await _update(tester);
      expect(find.byTooltip(_enter), findsOneWidget);
      expect(session.stops, 0);
      await tester.tap(find.byTooltip(_enter));
      await _update(tester);
      expect(find.byTooltip(_leave), findsOneWidget);
      // Remove the route tree directly, as can happen on application teardown.
      await tester.pumpWidget(const SizedBox());
      await _update(tester);
      expect(requests.last, isFalse);
      expect(session.starts, 1);
      expect(session.stops, 1);
    },
  );
}
