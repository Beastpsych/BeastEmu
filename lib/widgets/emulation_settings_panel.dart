import 'package:flutter/material.dart';

import 'package:beastemu/core/theme.dart';
import 'package:beastemu/services/emulation_settings.dart';

class EmulationSettingsPanel extends StatelessWidget {
  const EmulationSettingsPanel({super.key, required this.settings});

  final EmulationSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return Material(
          color: beastPanel,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Colors.white12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Áudio', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(child: Text('Volume geral')),
                    Text('${settings.volume}%'),
                  ],
                ),
                Slider(
                  value: settings.volume.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  activeColor: beastRed,
                  semanticFormatterCallback: (value) => '${value.round()}%',
                  onChanged: (value) => settings.setVolume(value.round()),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Silenciar áudio'),
                  value: settings.muted,
                  onChanged: settings.setMuted,
                ),
                const Divider(height: 30),
                Text('Vídeo', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                const Text('Escala da imagem'),
                DropdownButton<int>(
                  isExpanded: true,
                  value: settings.scale,
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('Ajustar ao espaço disponível'),
                    ),
                    for (var scale = 1; scale <= 4; scale++)
                      DropdownMenuItem(
                        value: scale,
                        child: Text(
                          '$scale×   (${160 * scale} × ${144 * scale})',
                        ),
                      ),
                  ],
                  onChanged: (scale) {
                    if (scale != null) settings.setScale(scale);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Suavizar pixels'),
                  value: settings.smooth,
                  onChanged: settings.setSmooth,
                ),
                if (settings.storageMessage case final message?)
                  Text(
                    message,
                    style: const TextStyle(color: Colors.amberAccent),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
