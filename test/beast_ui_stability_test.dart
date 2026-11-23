import 'dart:async';
import 'dart:io';

import 'package:beastemu/core/theme.dart';
import 'package:beastemu/main.dart';
import 'package:beastemu/services/emulation_settings.dart';
import 'package:beastemu/services/keyboard_bindings.dart';
import 'package:beastemu/services/sameboy_live_service.dart';
import 'package:beastemu/widgets/keyboard_settings_panel.dart';
import 'package:beastemu/widgets/sameboy_live_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _SlowCloseSession extends SameBoyLiveService {
  late void Function(String) reportError;
  final flushFinished = Completer<void>();
  int stops = 0;

  @override
  Future<void> start({
    required String romPath,
    int volume = 100,
    required void Function(Uint8List) onFrame,
    required void Function(String) onError,
  }) async {
    reportError = onError;
  }

  @override
  Future<void> stop() {
    stops++;
    return flushFinished.future;
  }
}

Future<void> _pumpTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('beast-ui-');
  });
  tearDown(() => directory.delete(recursive: true));

  for (final size in [const Size(1180, 760), const Size(520, 680)]) {
    testWidgets(
      'Configurações acessíveis com janela de ${size.width.toInt()} px',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          BeastEmuApp(
            settings: EmulationSettings(directory: directory),
            bindings: KeyboardBindings(directory: directory),
          ),
        );
        await tester.tap(find.byIcon(Icons.settings_outlined));
        await tester.pumpAndSettle();
        expect(find.text('Volume geral').hitTestable(), findsOneWidget);
        final slider = find.byType(Slider);
        expect(tester.widget<Slider>(slider).activeColor, beastRed);
        final rect = tester.getRect(slider);
        expect(rect.width, greaterThan(100));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(find.text('Escala da imagem').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Sobre o BeastEmu'));
        await tester.pumpAndSettle();
        expect(find.text('Sobre o BeastEmu'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Fechar'));
        await tester.pumpAndSettle();

        final edit = find.byTooltip('Remapear Start');
        await tester.scrollUntilVisible(
          edit.hitTestable(),
          220,
          scrollable: find
              .descendant(
                of: find.byKey(const PageStorageKey(3)),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(edit);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          tester.widget<AlertDialog>(find.byType(AlertDialog)).backgroundColor,
          beastPanel,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(KeyboardSettingsPanel), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'sessão exibe carregamento, erro consultável e aguarda a gravação final',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(820, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = _SlowCloseSession();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => SameBoyLiveDialog(
                    service: service,
                    settings: EmulationSettings(directory: directory),
                    bindings: KeyboardBindings(directory: directory),
                    romPath: 'stub.gb',
                    gameTitle: 'Cartucho de teste',
                  ),
                ),
                child: const Text('Jogar'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Jogar'));
      await _pumpTransition(tester);
      expect(find.text('Iniciando SameBoy…'), findsOneWidget);

      service.reportError('Diagnóstico sintético: falha de conexão.');
      await _pumpTransition(tester);
      expect(find.text('Iniciando SameBoy…'), findsNothing);
      expect(find.text('Detalhes').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Detalhes'));
      await _pumpTransition(tester);
      expect(
        find.textContaining('Diagnóstico sintético', findRichText: true),
        findsWidgets,
      );
      // The diagnostic dialog is a separate route; leave the session running.
      await tester.tap(find.text('Voltar'));
      await _pumpTransition(tester);

      await tester.tap(find.byTooltip('Fechar'));
      await _pumpTransition(tester);
      expect(find.text('Encerrando sessão…'), findsWidgets);
      expect(service.stops, 1);
      expect(find.byType(SameBoyLiveDialog), findsOneWidget);
      service.flushFinished.complete();
      await _pumpTransition(tester);
      expect(find.byType(SameBoyLiveDialog), findsNothing);
      expect(service.stops, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
