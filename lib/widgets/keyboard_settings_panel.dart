import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:beastemu/core/theme.dart';
import 'package:beastemu/services/keyboard_bindings.dart';

String gameBoyButtonLabel(GameBoyButton button) => button.label;

String keyboardKeyLabel(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.arrowUp) return '↑';
  if (key == LogicalKeyboardKey.arrowDown) return '↓';
  if (key == LogicalKeyboardKey.arrowLeft) return '←';
  if (key == LogicalKeyboardKey.arrowRight) return '→';
  if (key == LogicalKeyboardKey.shiftLeft) return 'Shift esq.';
  if (key == LogicalKeyboardKey.shiftRight) return 'Shift dir.';
  if (key == LogicalKeyboardKey.numpadEnter) return 'Enter numérico';
  if (key == LogicalKeyboardKey.space) return 'Espaço';
  return key.keyLabel;
}

class KeyboardSettingsPanel extends StatelessWidget {
  const KeyboardSettingsPanel({super.key, required this.bindings});
  final KeyboardBindings bindings;

  Future<void> _capture(
    BuildContext context,
    GameBoyButton? button, [
    EmulatorShortcut? shortcut,
  ]) async {
    final key = await showDialog<LogicalKeyboardKey>(
      context: context,
      builder: (_) =>
          _CaptureKey(bindings: bindings, button: button, shortcut: shortcut),
    );
    if (key == null || !context.mounted) return;
    if (button == null) {
      await bindings.bindShortcut(shortcut!, key);
    } else {
      await bindings.bind(button, key);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: bindings,
      builder: (context, _) => Material(
        color: beastPanel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Colors.white12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Teclado', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final button in GameBoyButton.values)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(gameBoyButtonLabel(button)),
                  subtitle: Text(
                    bindings
                        .keysFor(button)
                        .map(keyboardKeyLabel)
                        .join('  /  '),
                  ),
                  trailing: IconButton(
                    tooltip: 'Remapear ${gameBoyButtonLabel(button)}',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _capture(context, button),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: bindings.restoreDefaults,
                icon: const Icon(Icons.restore_outlined),
                label: const Text('Restaurar teclado padrão'),
              ),
              const Divider(),
              Text(
                'Atalhos do emulador',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final action in EmulatorShortcut.values)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(action.label),
                  subtitle: Text(switch (bindings.shortcutKey(action)) {
                    final key? => keyboardKeyLabel(key),
                    null => 'Sem tecla · padrão em uso',
                  }),
                  trailing: IconButton(
                    tooltip: 'Remapear ${action.label}',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _capture(context, null, action),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: bindings.restoreShortcuts,
                icon: const Icon(Icons.restore_outlined),
                label: const Text('Restaurar atalhos padrão'),
              ),
              if (bindings.storageMessage case final message?)
                Text(
                  message,
                  style: const TextStyle(color: Colors.amberAccent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptureKey extends StatefulWidget {
  const _CaptureKey({
    required this.bindings,
    required this.button,
    this.shortcut,
  });
  final KeyboardBindings bindings;
  final GameBoyButton? button;
  final EmulatorShortcut? shortcut;

  @override
  State<_CaptureKey> createState() => _CaptureKeyState();
}

class _CaptureKeyState extends State<_CaptureKey> {
  String? _error;

  @override
  void initState() {
    super.initState();
    // Capture Enter, Space and Tab before a focused dialog button or traversal
    // shortcut can consume the candidate key. Only the current route captures.
    FocusManager.instance.addEarlyKeyEventHandler(_handle);
  }

  KeyEventResult _handle(KeyEvent event) {
    if (ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
    } else {
      final error = KeyboardBindings.shortcutModifierPressed
          ? 'Pressione uma tecla sem Ctrl, Alt ou Windows.'
          : widget.bindings.validate(
              widget.button,
              key,
              shortcut: widget.shortcut,
            );
      if (error == null) {
        Navigator.pop(context, key);
      } else {
        setState(() => _error = error);
      }
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: beastPanel,
    title: Text('Remapear ${widget.button?.label ?? widget.shortcut!.label}'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Pressione a nova tecla ou Esc para cancelar.'),
        if (_error case final message?) ...[
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.amberAccent)),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
    ],
  );
}
