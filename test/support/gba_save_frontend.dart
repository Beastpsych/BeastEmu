import 'dart:async';
import 'dart:io';

import 'package:beastemu/services/sameboy_live_service.dart';

// Run in a fresh OS process on every invocation. Exercise the production
// launch, framebuffer decoder, input channel, profile and shutdown sequence.
Future<void> main(List<String> args) async {
  final profile = Directory(args[1]);
  final package = Platform.environment['BEASTEMU_TEST_PACKAGE'];
  final session = SameBoyLiveService(
    profileRoot: profile,
    appDirectory: package == null ? null : Directory(package),
  );
  final first = Completer<bool>(), green = Completer<void>();
  Object? failure;
  try {
    await session.start(
      romPath: args[0],
      volume: 0,
      onError: (error) {
        failure = error;
        if (!first.isCompleted) first.complete(false);
        if (!green.isCompleted) green.complete();
      },
      onFrame: (pixels) {
        final red = pixels[0] > 200 && pixels[1] < 30;
        final ok = pixels[1] > 200 && pixels[0] < 30;
        if ((red || ok) && !first.isCompleted) first.complete(ok);
        if (ok && !green.isCompleted) green.complete();
      },
    );
    final restored = await first.future.timeout(const Duration(seconds: 8));
    if (restored != (args[2] == 'restore') || failure != null) {
      throw StateError('Progresso inicial inesperado. $failure');
    }
    if (args[2] == 'write' || args[2] == 'periodic') {
      session.sendMask(1 << 8);
      await green.future.timeout(const Duration(seconds: 8));
      session.sendMask(0);
      if (args[2] == 'periodic') {
        final time = Stopwatch()..start();
        while (!session.gbaSaveStatus.startsWith('Cartucho salvo') &&
            time.elapsed < const Duration(seconds: 12)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (!session.gbaSaveStatus.startsWith('Cartucho salvo')) {
          throw StateError('Checkpoint periódico ausente.');
        }
      }
    }
    if (failure != null) throw StateError('$failure');
  } finally {
    await session.stop();
  }
}
