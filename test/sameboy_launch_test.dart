import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:beastemu/services/sameboy_launch.dart';

void main() {
  test(
    'pacote encontra os dois auxiliares fora do diretório corrente',
    () async {
      final app = await Directory.systemTemp.createTemp('beast package ');
      addTearDown(() => app.delete(recursive: true));
      final checkout = Directory('${app.path}/unrelated');
      await File('${app.path}/cores/windows/sameboy_libretro.dll')
          .create(recursive: true);
      await File('${app.path}/cores/windows/mgba_libretro.dll').create();
      await Directory('${app.path}/helpers').create();
      for (final helper in SameBoyHelper.values) {
        expect(
          () => SameBoyLaunch.resolve(
            helper,
            appDirectory: app,
            checkout: checkout,
          ),
          throwsStateError,
        );
        final file = await File('${app.path}/helpers/${helper.binary}.exe')
            .create();
        final command = SameBoyLaunch.resolve(
          helper,
          appDirectory: app,
          checkout: checkout,
        );
        expect(File(command.executable).uri, file.absolute.uri);
        expect(command.root.path, app.absolute.path);
        expect(command.prefix, isEmpty);
        expect(command.usesShell, false);
      }
    },
  );
}
