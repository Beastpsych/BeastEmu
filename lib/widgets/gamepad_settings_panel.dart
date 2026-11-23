import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/gamepads.dart';
import '../services/keyboard_bindings.dart';
import '../services/xinput.dart';

class GamepadSettingsPanel extends StatelessWidget {
  const GamepadSettingsPanel({super.key, required this.pads});
  final Gamepads pads;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pads,
      builder: (context, _) {
        final slots = pads.connected;
        return Material(
          color: beastPanel,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Controles Xbox / XInput',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (pads.deviceError != null)
                  Text(pads.deviceError!)
                else if (slots.isEmpty)
                  const Text('Nenhum controle XInput conectado.'),
                for (final slot in slots) _device(slot),
                const SizedBox(height: 12),
                const Text(
                  'O D-pad e o analógico esquerdo compartilham as direções. Escolher um botão já usado troca as duas associações.',
                ),
                for (final button in GameBoyButton.values)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(button.label),
                    subtitle: Text(pads.binding(button).label),
                    trailing: PopupMenuButton<PadControl>(
                      tooltip: 'Mapear controle · ${button.label}',
                      icon: const Icon(Icons.edit_outlined),
                      initialValue: pads.binding(button),
                      onSelected: (value) => pads.bind(button, value),
                      itemBuilder: (_) => [
                        for (final control in Gamepads.choices)
                          PopupMenuItem(
                            value: control,
                            child: Text(control.label),
                          ),
                      ],
                    ),
                  ),
                TextButton(
                  onPressed: pads.restore,
                  child: const Text('Restaurar controle padrão'),
                ),
                if (pads.storageError != null) Text(pads.storageError!),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _device(int slot) {
    final player = pads.slotFor(PadPlayer.one) == slot
        ? ' · Jogador 1'
        : pads.slotFor(PadPlayer.two) == slot
        ? ' · Jogador 2 (reservado)'
        : '';
    final pressed = PadControl.values.where((c) => pads.raw(slot) & c.bit != 0);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.sports_esports_outlined),
      title: Text('Controle ${slot + 1}$player'),
      subtitle: Text(
        pressed.isEmpty
            ? 'Em repouso'
            : pressed.map((c) => c.label).join('  ·  '),
      ),
    );
  }
}
