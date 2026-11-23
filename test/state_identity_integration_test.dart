import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beastemu/services/sameboy_commands.dart';
import 'package:beastemu/services/sameboy_launch.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sameboy_cartridge_integration_test.dart' show cartridge;

typedef Send = Future<Map> Function(int);

Future<void> runRom(
  Directory local,
  File rom,
  Future<void> Function(Send) check, {
  String? rejectedHash,
}) async {
  final app = Platform.environment['BEASTEMU_TEST_PACKAGE'];
  final launch = app == null
      ? null
      : SameBoyLaunch.resolve(SameBoyHelper.live, appDirectory: Directory(app));
  final config = jsonDecode(
    await File('.dart_tool/package_config.json').readAsString(),
  );
  final sdk = Directory.fromUri(Uri.parse(config['flutterRoot'] as String));
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final process = await Process.start(
    launch?.executable ?? '${sdk.path}/bin/cache/dart-sdk/bin/dart.exe',
    [
      if (launch == null) 'tool/stream_sameboy.dart',
      rom.path,
      '${server.port}',
    ],
    workingDirectory: launch?.root.path,
    environment: {
      'LOCALAPPDATA': local.path,
      sameBoyCommandEnvironment: '1',
      expectedRomEnvironment:
          rejectedHash ?? sha256.convert(await rom.readAsBytes()).toString(),
    },
  );
  final errors = process.stderr.transform(utf8.decoder).join();
  final replies = StreamIterator(
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((s) => s.startsWith(stateReplyPrefix)),
  );
  Socket? socket;
  try {
    if (rejectedHash != null) return;
    socket = await server.first.timeout(const Duration(seconds: 15));
    socket.listen((_) {});
    await check((cmd) async {
      process.stdin.add([cmd]);
      expect(
        await replies.moveNext().timeout(const Duration(seconds: 6)),
        true,
      );
      final data =
          jsonDecode(replies.current.substring(stateReplyPrefix.length)) as Map;
      expect(data['command'], cmd);
      return data;
    });
  } finally {
    socket?.destroy();
    await server.close();
    await replies.cancel();
    expect(
      await process.exitCode.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          process.kill();
          return -1;
        },
      ),
      rejectedHash == null ? 0 : 2,
      reason: await errors,
    );
    if (rejectedHash != null) {
      expect(await errors, contains('difere da entrada'));
    }
  }
}

void main() {
  test(
    'Red, Blue, Gold e Silver sintéticos isolam estados por conteúdo, inclusive após renomear',
    () async {
      final temp = await Directory.systemTemp.createTemp('beast-identity-');
      addTearDown(() => temp.delete(recursive: true));
      final files = <File>[];
      final folders = <Directory>[];
      for (final name in ['Red', 'Blue', 'Gold', 'Silver']) {
        final data = cartridge(files.length >= 2)..[0x4000] = files.length;
        final dir = await Directory('${temp.path}/$name').create();
        final rom = await File('${dir.path}/game.gb').writeAsBytes(data);
        if (files.isEmpty) {
          await runRom(
            temp,
            rom,
            (_) async => fail('Sessão indevida'),
            rejectedHash: '0' * 64,
          );
          expect(await Directory('${temp.path}/BeastEmu').exists(), isFalse);
        }
        files.add(rom);
        folders.add(
          Directory('${temp.path}/BeastEmu/states/${sha256.convert(data)}'),
        );
        await runRom(temp, rom, (send) async {
          expect((await send(listStateSlots))['slots'], List.filled(5, null));
          expect((await send(quickLoad))['empty'], true);
          expect((await send(quickSave))['error'], isNull);
          expect((await send(quickSave))['error'], isNull);
          expect((await send(listStateSlots))['slots'], List.filled(5, null));
          expect((await send(createStateBase + files.length))['error'], isNull);
        });
      }
      for (var i = 0; i < files.length; i++) {
        final renamed = await files[i].rename(
          '${files[i].parent.path}/renamed.gb',
        );
        await runRom(temp, renamed, (send) async {
          final slots = (await send(listStateSlots))['slots'] as List;
          expect(slots.length, 5);
          expect(slots.whereType<String>(), hasLength(1));
          expect(slots[i], isA<String>());
          expect((await send(quickLoad))['protected'], true);
          final quickFile = File('${folders[i].path}/quick.state');
          await File('${folders[(i + 1) % 4].path}/${(i + 1) % 4 + 1}.state')
              .copy(quickFile.path);
          final foreignQuick = await quickFile.readAsBytes();
          expect((await send(quickLoad))['error'], isNotNull);
          expect((await send(quickSave))['error'], isNotNull);
          expect(await quickFile.readAsBytes(), foreignQuick);
          final foreign = File(
            '${folders[(i + 1) % 4].path}/${(i + 1) % 4 + 1}.state',
          );
          final copied = await foreign.copy('${folders[i].path}/5.state');
          final original = await copied.readAsBytes();
          expect(
            (await send(listStateSlots))['slots'][4],
            contains('Incompatível'),
          );
          expect((await send(loadStateBase + 5))['error'], isNotNull);
          expect((await send(replaceStateBase + 5))['error'], isNotNull);
          expect(await copied.readAsBytes(), original);
          // A matching ROM and a valid checksum still require the exact core.
          final own = await File('${folders[i].path}/${i + 1}.state')
              .readAsBytes();
          own[36] ^= 1;
          final end = own.length - 32;
          own.setAll(end, sha256.convert(own.sublist(0, end)).bytes);
          await copied.writeAsBytes(own);
          expect((await send(loadStateBase + 5))['error'], isNotNull);
          expect(
            (await send(listStateSlots))['slots'][4],
            contains('Incompatível'),
          );
          expect((await send(replaceStateBase + 5))['error'], isNotNull);
          expect(await copied.readAsBytes(), own);
        });
      }
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
