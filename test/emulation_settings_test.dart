import 'dart:convert';
import 'dart:io';

import 'package:beastemu/services/emulation_settings.dart';
import 'package:beastemu/widgets/emulation_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('beast-settings-');
  });
  tearDown(() => directory.delete(recursive: true));

  test('volume, mudo, escala e filtro sobrevivem a outra instância', () async {
    final store = EmulationSettings(directory: directory);
    await store.load();
    expect(
      [store.volume, store.muted, store.scale, store.smooth],
      [100, false, 0, false],
    );
    await Future.wait([
      store.setVolume(62),
      store.setMuted(true),
      store.setScale(3),
      store.setSmooth(true),
      for (int i = 0; i <= 27; i++) store.setVolume(i),
    ]);
    final reopened = EmulationSettings(directory: directory);
    await reopened.load();
    expect(
      [
        reopened.volume,
        reopened.effectiveVolume,
        reopened.scale,
        reopened.smooth,
      ],
      [27, 0, 3, true],
    );
    await reopened.setMuted(false);
    expect(reopened.effectiveVolume, 27);
    expect(await directory.list().length, 1);
  });

  test(
    'preferências inválidas usam padrões seguros e preservam campos válidos',
    () async {
      final file = File('${directory.path}/emulation-settings-v1.json');
      await file.writeAsString(
        jsonEncode({'volume': -1, 'muted': 'sim', 'scale': 5, 'smooth': true}),
      );
      final store = EmulationSettings(directory: directory);
      await store.load();
      expect(
        [store.volume, store.muted, store.scale, store.smooth],
        [100, false, 0, true],
      );
      await store.setVolume(118);
      expect(store.volume, 100);
      await store.setVolume(-8);
      expect(store.volume, 0);
      await file.writeAsString('{');
      final recovered = EmulationSettings(directory: directory);
      await recovered.load();
      expect(recovered.scale, 0);
      expect(recovered.effectiveVolume, 100);
      expect(recovered.storageMessage, isNotNull);
    },
  );

  testWidgets('painel aplica volume e silencia preservando o nível escolhido', (
    tester,
  ) async {
    final store = EmulationSettings(directory: directory);
    await tester.runAsync(store.load);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EmulationSettingsPanel(settings: store)),
      ),
    );
    final slider = tester.widget<Slider>(find.byType(Slider));
    final mute = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Silenciar áudio'),
    );
    await tester.runAsync(() async {
      slider.onChanged!(41);
      mute.onChanged!(true);
      await store.setMuted(true);
    });
    await tester.pump();
    expect(find.text('41%'), findsOneWidget);
    expect(store.effectiveVolume, 0);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Silenciar áudio'),
          )
          .value,
      isTrue,
    );
    expect(find.text('Escala da imagem'), findsOneWidget);
    expect(find.text('Suavizar pixels'), findsOneWidget);
  });
}
