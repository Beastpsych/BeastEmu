import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:beastemu/services/sameboy_commands.dart';
import 'package:beastemu/services/sameboy_live_service.dart';

/// A fresh process represents a restarted application frontend. It exercises
/// the public service, its stdin state channel and the isolated helper.
Future<void> main(List<String> args) async {
  final profile = Directory(args[1]);
  final package = Platform.environment['BEASTEMU_TEST_PACKAGE'];
  final session = SameBoyLiveService(
    profileRoot: profile,
    appDirectory: package == null ? null : Directory(package),
  );
  final red = Completer<void>();
  final green = Completer<void>();
  Object? failure;
  try {
    await session.start(
      romPath: args[0],
      volume: 0,
      onError: (error) {
        failure = error;
        if (!red.isCompleted) red.complete();
        if (!green.isCompleted) green.complete();
      },
      onFrame: (Uint8List pixels) {
        if (pixels[0] > 200 && pixels[1] < 30 && !red.isCompleted) {
          red.complete();
        }
        if (pixels[1] > 200 && pixels[0] < 30 && !green.isCompleted) {
          green.complete();
        }
      },
    );
    switch (args[2]) {
      case 'save':
        await red.future.timeout(const Duration(seconds: 8));
        await session.stateCommand(createStateBase + 1);
        await session.stateCommand(quickSave);
        session.sendMask(1 << 8);
        await green.future.timeout(const Duration(seconds: 8));
        session.sendMask(0);
      case 'load':
        await green.future.timeout(const Duration(seconds: 8));
        await session.stateCommand(listStateSlots);
        await session.stateCommand(loadStateBase + 1);
        await red.future.timeout(const Duration(seconds: 8));
      case 'cart':
        await green.future.timeout(const Duration(seconds: 8));
      default:
        throw ArgumentError('Modo de teste desconhecido.');
    }
    if (failure != null) throw StateError('$failure');
  } finally {
    await session.stop();
  }
}
