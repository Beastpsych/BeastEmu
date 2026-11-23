import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:beastemu/services/rgba_frame_stream_decoder.dart';
import 'package:beastemu/services/sameboy_commands.dart';
import 'package:beastemu/services/sameboy_launch.dart';

import 'sameboy_cartridge_integration_test.dart' show cartridge;

void main() {
  test(
    'DLL restaura vídeo em 4× e preserva SRAM e RTC do MBC3',
    () async {
      final local = await Directory.systemTemp.createTemp('beast-states-');
      addTearDown(() => local.delete(recursive: true));
      final rom = File('${local.path}/state.gb');
      final bytes = cartridge(false);
      // A monochrome MBC3 exercises the visible DMG palette and the RTC.
      bytes[0x14d] -= 0x10 - bytes[0x147];
      bytes[0x147] = 0x10;
      // A changes a latch in WRAM, SRAM and the DMG palette. Releasing A
      // leaves the latch set, so only restoring the state can clear it.
      bytes.setAll(0x150, [
        0x3e, 10, 0xea, 0, 0, // enable SRAM
        0xaf, 0xea, 0, 0xc0, 0xea, 0, 0xa0, // clear both latches
        0x3e, 0x10, 0xe0, 0, // select JOYP action buttons
        0xf0, 0, 0xe6, 1, 0x20, 22, // skip updates if A is released
        0x3e, 0xff, 0xea, 0, 0xc0, 0xea, 0, 0xa0,
        0x3e, 8, 0xea, 0, 0x40, 0x3e, 42, 0xea, 0, 0xa0, // RTC seconds
        0xaf, 0xea, 0, 0x40, // select SRAM again
        0xfa, 0, 0xc0, 0xe0, 0x47, 0x18, 0xdd, // BGP = WRAM, poll again
      ]);
      await rom.writeAsBytes(bytes);
      final config = jsonDecode(
        await File('.dart_tool/package_config.json').readAsString(),
      );
      final sdk = Directory.fromUri(Uri.parse(config['flutterRoot'] as String));
      final package = Platform.environment['BEASTEMU_TEST_PACKAGE'];
      final app = package == null ? null : Directory(package);
      if (app != null) {
        expect(
          Directory('${app.path}/helpers').existsSync(),
          isTrue,
          reason: 'Pacote de teste sem auxiliares: ${app.path}',
        );
      }
      final launch = app == null
          ? null
          : SameBoyLaunch.resolve(SameBoyHelper.live, appDirectory: app);
      final audio = File(
        '${app?.path ?? 'build/windows/x64/runner/Release'}/beastemu_audio.dll',
      );
      final environment = {
        'LOCALAPPDATA': local.path,
        'BEASTEMU_VOLUME_V1': '0',
        if (audio.existsSync()) 'BEASTEMU_AUDIO_DLL': audio.absolute.path,
        sameBoyCommandEnvironment: '1',
        if (app != null) ...{
          'SystemRoot': Platform.environment['SystemRoot']!,
          'TEMP': local.path,
          'TMP': local.path,
          'PATH': '${Platform.environment['SystemRoot']}\\System32',
        },
      };
      if (app != null) {
        final preview = SameBoyLaunch.resolve(
          SameBoyHelper.preview,
          appDirectory: app,
        );
        final image = File('${local.path}/synthetic.bmp');
        final capture = await Process.run(
          preview.executable,
          [rom.path, image.path],
          workingDirectory: preview.root.path,
          environment: environment,
          includeParentEnvironment: false,
        );
        expect(capture.exitCode, 0, reason: capture.stderr.toString());
        expect((await image.readAsBytes()).take(2), [0x42, 0x4d]);
      }
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final process = await Process.start(
        launch?.executable ?? '${sdk.path}/bin/cache/dart-sdk/bin/dart.exe',
        [
          if (launch == null) 'tool/stream_sameboy.dart',
          rom.path,
          '${server.port}',
        ],
        workingDirectory: launch?.root.path,
        environment: environment,
        includeParentEnvironment: app == null,
      );
      final err = process.stderr.transform(utf8.decoder).join();
      final replies = StreamIterator(
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .where((s) => s.startsWith(stateReplyPrefix)),
      );
      Future<Map> send(int cmd) async {
        process.stdin.add([cmd]);
        expect(
          await replies.moveNext().timeout(const Duration(seconds: 5)),
          true,
        );
        final reply = jsonDecode(
          replies.current.substring(stateReplyPrefix.length),
        ) as Map;
        expect(reply['command'], cmd);
        return reply;
      }

      Socket? socket;
      final frames = StreamController<int>.broadcast();
      final decoder = RgbaFrameStreamDecoder();
      Future<int> waitFrame(bool Function(int) ok) =>
          frames.stream.firstWhere(ok).timeout(const Duration(seconds: 10));
      var passed = false;
      try {
        socket = await server.first.timeout(const Duration(seconds: 15));
        final video = socket.listen(
          (data) => decoder.add(
            data,
            (frame) => frames.add(frame[0] + frame[1] + frame[2]),
          ),
        );
        await frames.stream
            .skip(150)
            .first
            .timeout(const Duration(seconds: 25));
        final bright = await waitFrame((_) => true);
        expect((await send(listStateSlots))['slots'], List.filled(5, null));
        expect((await send(createStateBase + 3))['error'], isNull);
        expect((await send(createStateBase + 3))['error'], isNotNull);
        expect((await send(listStateSlots))['slots'][2], isA<String>());
        expect((await send(replaceStateBase + 3))['error'], isNull);
        await send(listStateSlots);
        socket.add([0, 1]); // Libretro A = bit 8
        final dark = await waitFrame((x) => x < bright - 128);
        final sinceRelease = Stopwatch()..start();
        socket.add([0, 0]);
        await frames.stream.skip(3).first;
        expect(await waitFrame((_) => true), dark);
        for (final speed in [speedDouble, speedTriple, speedQuad]) {
          process.stdin.add([speed, 0, 42]);
          await frames.stream.skip(2).first.timeout(const Duration(seconds: 5));
        }
        final result = await send(loadStateBase + 3);
        sinceRelease.stop();
        expect(result['error'], isNull);
        expect(result['protected'], true);
        await waitFrame((x) => x == bright);
        final cart = Directory('${local.path}/BeastEmu/saves')
            .listSync()
            .whereType<File>()
            .singleWhere((f) => f.path.endsWith('.cart'));
        final before = await cart.readAsBytes();
        expect(before[45], 255);
        final header = ByteData.sublistView(before);
        final ramSize = header.getUint32(37, Endian.little);
        final rtcSize = header.getUint32(41, Endian.little);
        expect(rtcSize, 32);
        // The running seconds register can tick between JOYP release and
        // the pre-restore flush, even when the test takes less than a second.
        final seconds = before[45 + ramSize];
        expect(seconds, lessThan(60));
        expect(
          (seconds - 42) % 60,
          lessThanOrEqualTo(sinceRelease.elapsed.inSeconds + 1),
        );
        process.stdin.add([speedNormal, 75]);
        await waitFrame((x) => x == bright);
        final slot = Directory('${local.path}/BeastEmu/states')
            .listSync(recursive: true)
            .whereType<File>()
            .singleWhere((f) => f.path.endsWith('.state'));
        final damaged = await slot.readAsBytes();
        damaged[100] ^= 1;
        await slot.writeAsBytes(damaged);
        expect((await send(loadStateBase + 3))['error'], isNotNull);
        expect(
          (await send(listStateSlots))['slots'][2],
          'Incompatível ou ilegível',
        );
        // A stalled renderer must not prevent helper commands or shutdown.
        video.pause();
        process.stdin.add([speedQuad, 20, 0, 42]);
        await Future<void>.delayed(const Duration(seconds: 2));
        expect((await send(listStateSlots))['protected'], true);
        video.resume();
        // Keep stdin open: closing TCP alone must terminate the helper.
        socket.destroy();
        expect(await process.exitCode.timeout(const Duration(seconds: 8)), 0);
        expect(await cart.readAsBytes(), before);
        passed = true;
      } finally {
        process.stdin.close().ignore();
        socket?.destroy();
        await server.close();
        await replies.cancel();
        await frames.close();
        final code = await process.exitCode.timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            process.kill();
            return -1;
          },
        );
        final errors = await err;
        if (passed) expect(code, 0, reason: errors);
        if (passed && app != null) {
          // The packaged smoke run uses the actual voice on this Windows host.
          expect(
            errors,
            matches(RegExp(r'XAudio2: frames submitted=[1-9]\d*')),
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 1)),
    skip:
        !Platform.isWindows ||
        !File('cores/windows/sameboy_libretro.dll').existsSync(),
  );
}
