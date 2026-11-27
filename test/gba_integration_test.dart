import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beastemu/services/gba_cartridge.dart';
import 'package:beastemu/services/gba_video.dart';
import 'package:beastemu/services/sameboy_commands.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/gba_demo.dart';

void main() {
  final app = Directory(Platform.environment['BEASTEMU_TEST_PACKAGE'] ?? '.')
      .absolute;
  final helper = File('${app.path}/helpers/mgba-live.exe');
  final script = File('tool/stream_mgba.dart').absolute.path;
  Future<Process> launch(
    Directory cwd,
    File rom,
    int port,
    Directory profile,
  ) => Process.start(
    helper.existsSync() ? helper.path : 'dart',
    [
      if (!helper.existsSync()) ...['run', script],
      rom.path,
      '$port',
    ],
    runInShell: !helper.existsSync(),
    workingDirectory: cwd.path,
    environment: {
      expectedRomEnvironment: sha256.convert(rom.readAsBytesSync()).toString(),
      'LOCALAPPDATA': profile.path,
      'BEASTEMU_AUDIO_DLL': '${app.path}/beastemu_audio.dll',
    },
  );

  test('Seleção por extensão e cabeçalho GBA', () {
    expect(coreForPath('a.GB'), CartridgeCore.sameBoy);
    expect(coreForPath('a.gBc'), CartridgeCore.sameBoy);
    expect(coreForPath('a.GBA'), CartridgeCore.mgba);
    expect(coreForPath('a.gba.zip'), isNull);
    expect(gbaTitle(gbaDemo()), 'BEAST INPUT');
    expect(() => gbaTitle(Uint8List(0xc0)), throwsFormatException);
  });

  test('Cabeçalho de geometria fragmentado, RGBA e limites', () {
    final video = GbaVideoDecoder();
    final frames = <Uint8List>[];
    for (final chunk in [
      [2],
      [0, 1],
      [0, 9, 8],
      [7, 6, 5, 4, 3, 2],
    ]) {
      video.add(Uint8List.fromList(chunk), frames.add);
    }
    expect((video.width, video.height), (2, 1));
    expect(frames.single, [9, 8, 7, 6, 5, 4, 3, 2]);
    expect(
      () => GbaVideoDecoder().add(Uint8List(4), frames.add),
      throwsFormatException,
    );
  });

  test(
    'mGBA x64 executa os dez botões, vídeo, áudio e encerra sem saves',
    () async {
      final temp = await Directory.systemTemp.createTemp('beast-gba-test-');
      final profile = await Directory('${temp.path}/profile').create();
      final rom = File('${temp.path}/demo.gba');
      await rom.writeAsBytes(gbaDemo());
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final connection = server.first;
      final proc = await launch(app, rom, server.port, profile);
      final output = proc.stdout.transform(utf8.decoder).join();
      final errors = proc.stderr.transform(utf8.decoder).join();
      Socket? socket;
      addTearDown(() async {
        socket?.destroy();
        await server.close();
        proc.kill();
        await proc.exitCode;
        await temp.delete(recursive: true);
      });
      socket = await Future.any([
        connection,
        proc.exitCode.then<Socket>(
          (c) async => throw StateError('mGBA encerrou ($c): ${await errors}'),
        ),
      ]).timeout(const Duration(seconds: 20));
      final video = GbaVideoDecoder();
      var desired = 0;
      var reached = Completer<void>();
      socket.listen(
        (buf) => video.add(buf, (frame) {
          expect((video.width, video.height), (240, 160));
          var active = 0;
          for (var i = 0; i < 10; i++) {
            final pos = ((16 * i + 8) * 240 + 120) * 4;
            if (frame[pos + 1] > 200 && frame[pos] < 32) {
              active |= 1 << i;
            } else if (frame[pos] < 100 ||
                frame[pos + 1] > 50 ||
                frame[pos + 2] > 50) {
              return;
            }
          }
          if (active == desired && !reached.isCompleted) reached.complete();
        }),
      );
      await reached.future.timeout(const Duration(seconds: 6));
      // KEYINPUT order: A,B,Select,Start,Right,Left,Up,Down,R,L.
      const ids = [8, 0, 2, 3, 7, 6, 4, 5, 11, 10];
      for (var i = 0; i <= ids.length; i++) {
        reached = Completer<void>();
        desired = i == ids.length ? 0 : 1 << i;
        final mask = i == ids.length ? 0 : 1 << ids[i];
        socket.add([mask & 255, mask >> 8]);
        await socket.flush();
        await reached.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw StateError('Tecla GBA $i'),
        );
      }
      socket.destroy();
      await proc.stdin.close();
      expect(await proc.exitCode.timeout(const Duration(seconds: 6)), 0);
      final log = await output;
      expect(log, contains('240x160'));
      expect(log, contains('65536.0 Hz'));
      expect(log, contains('mGBA encerrado'));
      expect(log, matches(RegExp(r'[1-9]\d* amostras estéreo')));
      printOnFailure(log);
      expect(
        await profile
            .list(recursive: true)
            .where((e) => e is File && !e.path.endsWith('cart.lock'))
            .toList(),
        isEmpty,
      );
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'Auxiliar recusa DLL ausente, DLL trocada e cartucho inválido',
    () async {
      final temp = await Directory.systemTemp.createTemp('beast-gba-errors-');
      addTearDown(() => temp.delete(recursive: true));
      final core = File('${temp.path}/cores/windows/mgba_libretro.dll');
      final rom = File('${temp.path}/invalid.gba');
      Future<void> fails(String message) async {
        final proc = await launch(temp, rom, 1, temp);
        final error = proc.stderr.transform(utf8.decoder).join();
        final output = proc.stdout.drain<void>();
        expect(
          await proc.exitCode.timeout(const Duration(seconds: 15)),
          isNot(0),
        );
        await output;
        expect(await error, contains(message));
      }

      await rom.writeAsBytes(gbaDemo());
      await fails('DLL mGBA ausente');
      await core.create(recursive: true);
      await core.writeAsBytes([0, 1, 2]);
      await fails('DLL mGBA incompatível');
      await rom.writeAsBytes([0, 1, 2]);
      await fails('Cabeçalho GBA inválido');
      // A synthetic interrupt vector table looks like a BIOS to mGBA; it
      // passes the frontend header check and exercises retro_load_game=false.
      final biosLike = gbaDemo();
      for (var i = 0; i < 7; i++) {
        biosLike[4 * i + 2] = 0;
        biosLike[4 * i + 3] = 0xea;
      }
      await rom.writeAsBytes(biosLike);
      await File('${app.path}/cores/windows/mgba_libretro.dll').copy(core.path);
      await fails('mGBA recusou a ROM');
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
