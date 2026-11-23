import 'package:beastemu/services/keyboard_bindings.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:beastemu/main.dart';
import 'package:beastemu/services/emulation_settings.dart';

void main() {
  testWidgets('BeastEmu abre a tela inicial', (tester) async {
    // Inicializa nosso aplicativo.
    await tester.pumpWidget(BeastEmuApp(settings: EmulationSettings(), bindings: KeyboardBindings()));

    // Verifica se o banner principal aparece.
    expect(
      find.text('Todos os seus jogos.\nUm só lugar.'),
      findsOneWidget,
    );
  });
}
