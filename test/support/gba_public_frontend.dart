import 'dart:async';
import 'dart:io';

import 'package:beastemu/services/sameboy_commands.dart';
import 'package:beastemu/services/sameboy_live_service.dart';

Future<void> main(List<String> args) async {
  final app = Platform.environment['BEASTEMU_TEST_PACKAGE'];
  final service = SameBoyLiveService(
    appDirectory: app == null ? null : Directory(app),
  );
  final green = Completer<void>();
  String? error;
  try {
    await service.start(
      romPath: args[0],
      volume: 0,
      onFrame: (pixels) {
        if (pixels[1] > 200 && pixels[0] < 30 && !green.isCompleted) {
          green.complete();
        }
      },
      onError: (e) {
        error = e;
        if (!green.isCompleted) green.complete();
      },
    );
    await green.future.timeout(const Duration(seconds: 10));
    if (error != null) throw StateError(error!);
    await service.stateCommand(quickLoad);
    if (!service.cartridgeProtected) throw StateError('Cartucho sem proteção.');
  } finally {
    await service.stop();
  }
}
