import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beastemu/services/gba_video.dart';
import 'package:beastemu/services/sameboy_commands.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/gba_save_rom.dart';

void main() {
  final app = Directory(Platform.environment['BEASTEMU_TEST_PACKAGE'] ?? '.')
      .absolute;
  final helper = File('${app.path}/helpers/mgba-live.exe');
  final script = File('tool/stream_mgba.dart').absolute.path;

  Future<Process> launch(Directory profile, File rom, int port) =>
      Process.start(
        helper.existsSync() ? helper.path : 'dart',
        [
          if (!helper.existsSync()) ...['run', script],
          rom.path,
          '$port',
        ],
        runInShell: !helper.existsSync(),
        workingDirectory: app.path,
        environment: {
          'LOCALAPPDATA': '${profile.path}/BeastEmu-GBA-Dev',
          sameBoyCommandEnvironment: '1',
          'BEASTEMU_AUDIO_DLL': '${app.path}/beastemu_audio.dll',
        },
      );

  for (final saveSize in [512, 8192, 32768, 65536, 131072]) {
    test(
      'mGBA $saveSize restaura slots e rápido, rejeita estados inválidos e protege cartucho',
      () async {
        final temp = await Directory.systemTemp.createTemp('beast-gba-state-');
        addTearDown(() => temp.delete(recursive: true));
        final rom = File('${temp.path}/state.gba');
        final bytes = gbaSaveRom(saveSize);
        await rom.writeAsBytes(bytes);
        final profile = Directory('${temp.path}/profile');
        final states = Directory(
          '${profile.path}/BeastEmu-GBA-Dev/BeastEmu/states/mgba/${sha256.convert(bytes)}',
        );
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final process = await launch(profile, rom, server.port);
        final stderr = process.stderr.transform(utf8.decoder).join();
        final replies = StreamIterator(
          process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .where((line) => line.startsWith(stateReplyPrefix)),
        );
        Socket? socket;
        try {
          socket = await server.first.timeout(const Duration(seconds: 15));
          final red = Completer<void>();
          final green = Completer<void>();
          final restoredRed = Completer<void>();
          final video = GbaVideoDecoder();
          socket.listen(
            (data) => video.add(data, (frame) {
              if (frame[0] > 200 && frame[1] < 30 && !red.isCompleted) {
                red.complete();
              }
              if (frame[0] > 200 &&
                  frame[1] < 30 &&
                  green.isCompleted &&
                  !restoredRed.isCompleted) {
                restoredRed.complete();
              }
              if (frame[1] > 200 && frame[0] < 30 && !green.isCompleted) {
                green.complete();
              }
            }),
          );
          Future<Map> send(int command) async {
            process.stdin.add([command]);
            expect(
              await replies.moveNext().timeout(const Duration(seconds: 8)),
              isTrue,
            );
            final reply = jsonDecode(
              replies.current.substring(stateReplyPrefix.length),
            ) as Map;
            expect(reply['command'], command);
            return reply;
          }

          await red.future.timeout(const Duration(seconds: 10));
          process.stdin.add([speedDouble]);
          expect((await send(listStateSlots))['slots'], List.filled(5, null));
          expect((await send(quickLoad))['empty'], isTrue);
          expect((await send(loadStateBase + 1))['error'], isNotNull);
          for (var slot = 1; slot <= 5; slot++) {
            expect((await send(createStateBase + slot))['error'], isNull);
          }
          expect((await send(createStateBase + 1))['error'], isNotNull);
          expect(
            (await send(listStateSlots))['slots'].whereType<String>(),
            hasLength(5),
          );
          expect((await send(replaceStateBase + 1))['error'], isNull);
          expect((await send(quickSave))['error'], isNull);
          expect(
            (await send(listStateSlots))['slots'].whereType<String>(),
            hasLength(5),
          );
          socket.add([0, 1]);
          process.stdin.add([speedTriple]);
          await green.future.timeout(const Duration(seconds: 10));
          socket.add([0, 0]);
          await socket.flush();
          await Future<void>.delayed(const Duration(milliseconds: 200));
          final restored = await send(loadStateBase + 1);
          expect(restored['error'], isNull);
          expect(restored['protected'], isTrue);
          await restoredRed.future.timeout(const Duration(seconds: 10));
          expect((await send(quickLoad))['error'], isNull);
          process.stdin.add([speedQuad]);
          expect((await send(quickSave))['error'], isNull);
          process.stdin.add([speedNormal]);
          final restoredSnapshot = await File('${states.path}/quick.state')
              .readAsBytes();
          final restoredHeader = ByteData.sublistView(restoredSnapshot);
          final nativeLength = restoredHeader.getUint32(110, Endian.little);
          final cartLength = restoredHeader.getUint32(114, Endian.little);
          // The initial Flash state may still be 64 KiB: the synthetic game
          // reaches bank 1 only after the first marker write.
          expect(cartLength, saveSize == 131072 ? 65536 : saveSize);
          expect(
            restoredSnapshot
                .sublist(118 + nativeLength, 118 + nativeLength + cartLength)
                .every((v) => v == 255),
            isTrue,
          );
          // Cross a periodic checkpoint after restore. It must preserve the
          // latest normal save while the old state continues to run.
          await Future<void>.delayed(const Duration(seconds: 6));

          final slot = File('${states.path}/1.state');
          final original = await slot.readAsBytes();
          final corrupted = Uint8List.fromList(original)..[120] ^= 1;
          await slot.writeAsBytes(corrupted);
          expect((await send(loadStateBase + 1))['error'], isNotNull);
          expect(await slot.readAsBytes(), corrupted);
          expect(
            (await send(listStateSlots))['slots'][0],
            contains('Incompatível'),
          );
          await slot.writeAsBytes(original);

          socket.destroy();
          await process.stdin.close();
          expect(
            await process.exitCode.timeout(const Duration(seconds: 12)),
            0,
            reason: await stderr,
          );
        } finally {
          socket?.destroy();
          await server.close();
          await replies.cancel();
          if (process.kill()) await process.exitCode;
        }

        Future<void> restart(File target, String mode) async {
          final result = await Process.run(
            'dart',
            [
              'run',
              'test/support/gba_state_frontend.dart',
              target.path,
              profile.path,
              mode,
            ],
            runInShell: true,
            environment: {
              ...Platform.environment,
              'BEASTEMU_TEST_PACKAGE': app.path,
            },
          );
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
        }

        await restart(rom, 'load');
        await restart(rom, 'cart');
        final state = File('${states.path}/1.state');
        final other = File('${temp.path}/other.gba');
        final otherBytes = gbaSaveRom(saveSize, variant: 1);
        await other.writeAsBytes(otherBytes);
        await restart(other, 'save');
        final otherState = File(
          '${profile.path}/BeastEmu-GBA-Dev/BeastEmu/states/mgba/${sha256.convert(otherBytes)}/1.state',
        );
        await otherState.copy(state.path);
        await _expectRefusal(profile, rom, state, loadStateBase + 1);
        final foreign = await File('${states.path}/2.state').readAsBytes();
        foreign[37] ^= 1;
        foreign[101] = 1;
        foreign.setAll(
          foreign.length - 32,
          sha256.convert(foreign.sublist(0, foreign.length - 32)).bytes,
        );
        await state.writeAsBytes(foreign);
        await _expectRefusal(profile, rom, state, loadStateBase + 1);
      },
      skip: !Platform.isWindows,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}

Future<void> _expectRefusal(
  Directory profile,
  File rom,
  File state,
  int command,
) async {
  final before = await state.readAsBytes();
  final app = Directory(Platform.environment['BEASTEMU_TEST_PACKAGE'] ?? '.')
      .absolute;
  final helper = File('${app.path}/helpers/mgba-live.exe');
  final script = File('tool/stream_mgba.dart').absolute.path;
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final confirm = await Process.start(
    helper.existsSync() ? helper.path : 'dart',
    [
      if (!helper.existsSync()) ...['run', script],
      rom.path,
      '${server.port}',
    ],
    runInShell: !helper.existsSync(),
    workingDirectory: app.path,
    environment: {
      'LOCALAPPDATA': '${profile.path}/BeastEmu-GBA-Dev',
      sameBoyCommandEnvironment: '1',
      'BEASTEMU_AUDIO_DLL': '${app.path}/beastemu_audio.dll',
    },
  );
  final output = StreamIterator(
    confirm.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.startsWith(stateReplyPrefix)),
  );
  Socket? connection;
  try {
    connection = await server.first.timeout(const Duration(seconds: 15));
    connection.listen((_) {});
    confirm.stdin.add([command]);
    expect(await output.moveNext().timeout(const Duration(seconds: 8)), isTrue);
    final refused =
        jsonDecode(output.current.substring(stateReplyPrefix.length)) as Map;
    expect(refused['error'], isNotNull);
    expect(await state.readAsBytes(), before);
  } finally {
    connection?.destroy();
    await confirm.stdin.close();
    expect(await confirm.exitCode.timeout(const Duration(seconds: 12)), 0);
    await output.cancel();
    await server.close();
  }
}
