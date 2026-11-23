import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beastemu/services/rgba_frame_stream_decoder.dart';
import 'package:beastemu/services/sameboy_link_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/link_demo_roms.dart' show serialCartridge;

Future<Process> startDual(
  Directory temp,
  File left,
  File right,
  int port,
) async {
  final config = jsonDecode(
    await File('.dart_tool/package_config.json').readAsString(),
  );
  final sdk = Directory.fromUri(Uri.parse(config['flutterRoot'] as String));
  final package = Platform.environment['BEASTEMU_TEST_PACKAGE'];
  return Process.start(
    package == null
        ? '${sdk.path}/bin/cache/dart-sdk/bin/dart.exe'
        : '$package/helpers/sameboy-live.exe',
    [
      if (package == null) 'tool/stream_sameboy.dart',
      linkLaunchFlag,
      left.path,
      right.path,
      '$port',
    ],
    workingDirectory: package,
    environment: {
      'LOCALAPPDATA': temp.path,
      'BEASTEMU_VOLUME_V1': '0',
      'BEASTEMU_COMMANDS_V2': '1',
      'BEASTEMU_AUDIO_DLL':
          '${package ?? Directory('build/windows/x64/runner/Release').absolute.path}/beastemu_audio.dll',
    },
  );
}

Future<void> exchange(Directory temp, File left, File right) async {
  final package = Platform.environment['BEASTEMU_TEST_PACKAGE'];
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(server.close);
  final process = await startDual(temp, left, right, server.port);
  final log = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  final output = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  Socket? socket;
  final seen = StreamController<(int, int)>.broadcast();
  try {
    socket = await server.first.timeout(const Duration(seconds: 12));
    final decoder = RgbaFrameStreamDecoder(
      bytesPerFrame: linkWidth * linkHeight * 4,
    );
    socket.listen(
      (chunk) => decoder.add(chunk, (frame) {
        int brightness(int offset) =>
            frame[offset] + frame[offset + 1] + frame[offset + 2];
        seen.add((brightness(0), brightness(160 * 4)));
      }),
      onDone: seen.close,
      onError: seen.addError,
    );
    // Wait for both boot ROMs to finish, then arm only the right cartridge.
    final idle = await seen.stream
        .skip(145)
        .first
        .timeout(const Duration(seconds: 22));
    socket.add([0, 0, 1]); // split the 4-byte packet across socket writes
    await socket.flush();
    socket.add([0]);
    final ready = await seen.stream
        .firstWhere((f) => f.$1 == idle.$1 && f.$2 < idle.$2 - 40)
        .timeout(const Duration(seconds: 8));
    socket.add([0, 1, 0, 0]); // P1 presses A, P2 releases B
    await seen.stream
        .firstWhere((f) => f.$1 < idle.$1 - 128 && f.$2 < ready.$2 - 40)
        .timeout(const Duration(seconds: 8));
    process.stdin.add([145, 129]); // dual ignores speed and state commands
    await seen.stream.skip(4).first.timeout(const Duration(seconds: 3));
    socket.destroy();
    expect(
      await process.exitCode.timeout(const Duration(seconds: 10)),
      0,
      reason: await log,
    );
    final diagnostics = await output;
    expect(
      diagnostics,
      matches(RegExp(r'Audio/120 retro_run: [1-9]\d* stereo frames')),
    );
    if (package != null) {
      expect(diagnostics, contains('XAudio2 ativo: PCM estereo, 48000 Hz.'));
      expect(await log, matches(RegExp(r'XAudio2: frames submitted=[1-9]\d*')));
    }
  } finally {
    socket?.destroy();
    process.stdin.close().ignore();
    await server.close();
    await process.exitCode.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    final errors = await log;
    if (errors.contains('Erro SameBoy')) fail(errors);
  }
}

void main() {
  test(
    'Link v1 aguarda o par completo antes de publicar os dois controles',
    () {
      final input = JoypadPackets(dual: true)..add([1, 1, 2]);
      expect(input.masks, [0, 0]);
      input.add([1, 3, 0, 4, 0, 5]);
      expect(input.masks, [3, 4]);
      input.add([0, 6, 0]);
      expect(input.masks, [5, 6]);
    },
  );
  for (final identical in [false, true]) {
    test(
      'Link serial, telas, SRAM e RTC independentes — ${identical ? "mesma ROM" : "GB + GBC"}',
      () async {
        final temp = await Directory.systemTemp.createTemp('beast-link-');
        addTearDown(() => temp.delete(recursive: true));
        final left = File('${temp.path}/left.gb');
        await left.writeAsBytes(
          serialCartridge(color: false, masterByte: 0xa6, slaveByte: 0x37),
        );
        final right = identical ? left : File('${temp.path}/right.gbc');
        if (!identical) {
          await right.writeAsBytes(
            serialCartridge(color: true, masterByte: 0x83, slaveByte: 0x59),
          );
        }
        final root = Directory('${temp.path}/BeastEmu/saves');
        await root.create(recursive: true);
        final hash = sha256.convert(await left.readAsBytes());
        final single = File('${root.path}/$hash.cart');
        await single.writeAsBytes([11, 22, 33]);
        final expected = [identical ? 0x37 : 0x59, 0xa6];
        for (var run = 0; run < (identical ? 2 : 1); run++) {
          await exchange(temp, left, right);
          for (var port = 0; port < 2; port++) {
            final rom = port == 0 ? left : right;
            final id = sha256.convert(await rom.readAsBytes());
            final file = File('${root.path}/link/p${port + 1}/$id.cart');
            final data = await file.readAsBytes();
            final header = ByteData.sublistView(data);
            expect(header.getUint32(37, Endian.little), 32768);
            expect(header.getUint32(41, Endian.little), 32);
            expect(
              data[45],
              expected[port],
              reason: 'SB recebido no jogador ${port + 1}',
            );
            expect(data[46], port + 1);
            final sec = port == 0 ? 12 : 42;
            expect((data[45 + 32768] - sec) % 60, lessThan(5));
            if (run > 0) {
              expect(data[50], expected[port]);
              expect((data[51] - sec) % 60, lessThan(20));
            }
          }
        }
        expect(await single.readAsBytes(), [11, 22, 33]);
        expect(Directory('${temp.path}/BeastEmu/states').existsSync(), isFalse);
        if (identical) {
          // A damaged P2 save must abort startup and release P1's restored save.
          final first = File('${root.path}/link/p1/$hash.cart');
          final original = await first.readAsBytes();
          final damaged = File('${root.path}/link/p2/$hash.cart');
          await damaged.writeAsBytes([9, 8, 7]);
          final server = await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          addTearDown(server.close);
          final process = await startDual(temp, left, right, server.port);
          final errors = process.stderr
              .transform(const Utf8Decoder(allowMalformed: true))
              .join();
          final output = process.stdout.drain<void>();
          final peer = await server.first.timeout(const Duration(seconds: 12));
          try {
            expect(
              await process.exitCode.timeout(const Duration(seconds: 8)),
              isNot(0),
            );
            expect(await errors, contains('Tamanho de save incompativel'));
            await output;
          } finally {
            peer.destroy();
            process.stdin.close().ignore();
            await process.exitCode.timeout(
              const Duration(seconds: 3),
              onTimeout: () {
                process.kill();
                return -1;
              },
            );
          }
          expect(await damaged.readAsBytes(), [9, 8, 7]);
          expect(await first.readAsBytes(), original);
          final lock = await File('${first.path}.lock')
              .open(mode: FileMode.append);
          try {
            await lock.lock(FileLock.exclusive);
          } finally {
            await lock.close();
          }
        }
      },
      skip: !Platform.isWindows,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
