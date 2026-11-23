import 'package:beastemu/widgets/keyboard_settings_panel.dart';
import 'package:flutter/material.dart';


import 'package:beastemu/core/theme.dart';
import 'package:beastemu/services/gameboy_input_controller.dart';

/// Ferramenta de diagnóstico do teclado. Não executa a emulação.
class GameBoyKeyboardTestDialog extends StatefulWidget {
  const GameBoyKeyboardTestDialog({super.key, required this.bindings});
  final KeyboardBindings bindings;

  @override
  State<GameBoyKeyboardTestDialog> createState() =>
      _GameBoyKeyboardTestDialogState();
}

class _GameBoyKeyboardTestDialogState
    extends State<GameBoyKeyboardTestDialog> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Teclado Game Boy');
  late final _input = GameBoyInputController(bindings: widget.bindings);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Widget _key(GameBoyButton button, String label) {
    final pressed = _input.isPressed(button);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: pressed ? beastRed : beastPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: pressed ? Colors.redAccent : Colors.white24,
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: KeyboardListener(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: (KeyEvent event) {
              _input.handleKeyEvent(event);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _focusNode.requestFocus,
              child: AnimatedBuilder(
                animation: _input,
                builder: (context, _) {
                  final pressed = GameBoyButton.values
                      .where(_input.isPressed)
                      .map((button) => button.name.toUpperCase())
                      .join(', ');
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BEASTEMU  |  TESTE DE CONTROLES',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Clique nesta área e pressione as teclas. '
                        'Os botões ficarão vermelhos enquanto estiverem pressionados.',
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final button in GameBoyButton.values)
                            _key(button, '${gameBoyButtonLabel(button)} = ${widget.bindings.keysFor(button).map(keyboardKeyLabel).join(" / ")}'),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Pressionados: ${pressed.isEmpty ? 'nenhum' : pressed}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Este teste usa o mapeamento da sessão de jogo.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () {
                              _input.reset();
                              _focusNode.requestFocus();
                            },
                            child: const Text('Limpar e focar'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Fechar'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
