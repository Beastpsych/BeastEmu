import 'package:beastemu/services/keyboard_bindings.dart';
import 'package:beastemu/widgets/keyboard_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The widget test drives keyboard events through the real capture route.
// Storage round trips are covered separately by the bindings tests.
class _TestBindings extends KeyboardBindings {
  final _assigned = <GameBoyButton, LogicalKeyboardKey>{};

  @override
  List<LogicalKeyboardKey> keysFor(GameBoyButton button) =>
      _assigned.containsKey(button)
      ? [_assigned[button]!]
      : super.keysFor(button);

  @override
  Future<void> bind(GameBoyButton button, LogicalKeyboardKey key) async {
    _assigned[button] = key;
    notifyListeners();
  }

  @override
  Future<void> restoreDefaults() async {
    _assigned.clear();
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'captura mantém conflito, cancela com Esc e aplica tecla válida',
    (tester) async {
      final bindings = _TestBindings();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KeyboardSettingsPanel(bindings: bindings),
            ),
          ),
        ),
      );
      Future<void> openCapture() async {
        final edit = find.byTooltip('Remapear A');
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
      }

      for (final button in GameBoyButton.values) {
        expect(
          find.byTooltip('Remapear ${gameBoyButtonLabel(button)}'),
          findsOneWidget,
        );
      }
      await openCapture();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pump();
      expect(
        find.text(bindings.validate(GameBoyButton.a, LogicalKeyboardKey.keyZ)!),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pump();
      expect(
        find.text(bindings.validate(GameBoyButton.a, LogicalKeyboardKey.f11)!),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(bindings.keysFor(GameBoyButton.a), [LogicalKeyboardKey.keyX]);

      await openCapture();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(bindings.keysFor(GameBoyButton.a), [LogicalKeyboardKey.keyG]);
      expect(find.text('G'), findsOneWidget);

      final restore = find.text('Restaurar teclado padrão');
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(bindings.keysFor(GameBoyButton.a), [LogicalKeyboardKey.keyX]);
    },
  );
}
