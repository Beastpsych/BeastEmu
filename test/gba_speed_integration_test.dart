import 'dart:convert';
import 'dart:io';

import 'package:beastemu/services/sameboy_commands.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/gba_demo.dart';

void main() {
  test(
    'mGBA mede execução real 1×–4×, descarta PCM e restaura volume',
    () async {
      final temp = await Directory.systemTemp.createTemp('beast-gba-speed-');
      final app = Directory(
        Platform.environment['BEASTEMU_TEST_PACKAGE'] ?? '.',
      ).absolute;
      final helper = File('${app.path}/helpers/mgba-live.exe');
      final rom = File('${temp.path}/demo.gba');
      await rom.writeAsBytes(gbaDemo());
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final connected = server.first;
      final process = await Process.start(
        helper.existsSync() ? helper.path : 'dart',
        [
          if (!helper.existsSync()) ...[
            'run',
            File('tool/stream_mgba.dart').absolute.path,
          ],
          rom.path,
          '${server.port}',
        ],
        workingDirectory: app.path,
        runInShell: !helper.existsSync(),
        environment: {
          'LOCALAPPDATA': temp.path,
          'BEASTEMU_AUDIO_DLL': '${app.path}/beastemu_audio.dll',
          'BEASTEMU_VOLUME_V1': '36',
        },
      );
      final output = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      final reports = <Map>[];
      var audioStarted = false;
      final errors = process.stderr.transform(utf8.decoder).join();
      final drained = output.forEach((line) {
        if (line.contains('XAudio2 ativo: PCM estereo, 65536 Hz')) {
          audioStarted = true;
        }
        if (line.startsWith('GBA_SPEED ')) {
          reports.add(jsonDecode(line.substring(10)) as Map);
        }
      });
      Socket? socket;
      try {
        socket = await connected.timeout(const Duration(seconds: 15));
        socket.listen((_) {});
        // The report counts actual retro_run invocations, regardless of frames
        // skipped by the renderer. Each speed is measured for two wall seconds.
        for (final speed in [1, 2, 3, 4, 1]) {
          process.stdin.add([speedNormal + speed - 1]);
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        process.stdin.add([0, speedQuad]);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        process.stdin.add([speedNormal]);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        socket.destroy();
        await process.stdin.close();
        expect(await process.exitCode.timeout(const Duration(seconds: 12)), 0);
        await drained;
        for (var i = 0; i < 5; i++) {
          final r = reports[i];
          final speed = [1, 2, 3, 4, 1][i];
          final fps = (r['frames'] as int) * 1000000 / (r['us'] as int);
          stdout.writeln(
            'mGBA ${speed}x: ${fps.toStringAsFixed(2)} retro_run/s',
          );
          expect(r['speed'], speed);
          expect(fps, greaterThan(59.7275 * speed * .70));
          expect(fps, lessThan(59.7275 * speed * 1.20));
          expect(r['volume'], speed == 1 ? 36 : 0);
        }
        expect(reports.last['volume'], 0); // user mute survives acceleration
        expect(audioStarted, isTrue);
        final nativeLog = await errors;
        expect(nativeLog, isNot(contains('XAudio2 interrompido')));
        expect(nativeLog, matches(RegExp(r'frames submitted=[1-9]\d*')));
      } finally {
        socket?.destroy();
        process.kill();
        await process.exitCode;
        await server.close();
        await temp.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
