import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../tool/synthetic_gb.dart';

// Synthetic 32 KiB cartridge. Its program records a boot count and the
// latched MBC3 seconds register in SRAM; no commercial game data is needed.
Uint8List cartridge(bool clock) {
  final rom = syntheticHeader(color: clock, mapper: clock ? 0x10 : 3);
  final init = [
    if (clock) ...[
      0x3e,
      8,
      0xea,
      0,
      0x40,
      0x3e,
      17,
      0xea,
      0,
      0xa0,
      0xaf,
      0xea,
      0,
      0x40,
    ],
    0x3e,
    0x51,
    0xea,
    0,
    0xa0,
    0xaf,
    0xea,
    1,
    0xa0,
  ];
  rom.setAll(0x150, [
    0x3e, 10, 0xea, 0, 0, // Enable cartridge RAM.
    0xfa, 0, 0xa0, 0xfe, 0x51, 0x28, init.length, ...init,
    0x21, 1, 0xa0, 0x34, // INC (A001)
    if (clock) ...[
      0xaf, 0xea, 0, 0x60, 0x3c, 0xea, 0, 0x60, // latch 0 -> 1
      0x3e, 8, 0xea, 0, 0x40, 0xfa, 0, 0xa0, 0x47,
      0xaf, 0xea, 0, 0x40, 0x78, 0xea, 2, 0xa0, // SRAM[2] = seconds
    ],
    0x18, 0xfe,
  ]);
  return rom;
}

Future<void> session(
  Directory local,
  File rom,
  int videoFrames, {
  Future<void> Function()? beforeClose,
}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final config = jsonDecode(
    await File('.dart_tool/package_config.json').readAsString(),
  );
  final sdk = Directory.fromUri(Uri.parse(config['flutterRoot'] as String));
  final process = await Process.start(
    '${sdk.path}/bin/cache/dart-sdk/bin/dart.exe',
    ['tool/stream_sameboy.dart', rom.path, '${server.port}'],
    environment: {'LOCALAPPDATA': local.path},
  );
  final errors = process.stderr.transform(utf8.decoder).join();
  final output = process.stdout.drain<void>();
  Socket? socket;
  try {
    socket = await server.first.timeout(const Duration(seconds: 20));
    var bytes = 0;
    final ready = Completer<void>();
    socket.listen(
      (chunk) {
        bytes += chunk.length;
        if (bytes >= videoFrames * 160 * 144 * 4 && !ready.isCompleted) {
          ready.complete();
        }
      },
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(StateError('Helper exited early'));
        }
      },
    );
    await ready.future.timeout(const Duration(seconds: 20));
    await beforeClose?.call();
  } finally {
    socket?.destroy();
    await server.close();
    final code = await process.exitCode.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await output;
    expect(code, 0, reason: await errors);
  }
}

void main() {
  for (final clock in [false, true]) {
    test(
      'DLL restores ${clock ? "MBC3 RAM + RTC" : "MBC1 RAM"} across processes',
      () async {
        final local = await Directory.systemTemp.createTemp('beast-cart-');
        addTearDown(() => local.delete(recursive: true));
        final rom = File('${local.path}/test.${clock ? "gbc" : "gb"}');
        await rom.writeAsBytes(cartridge(clock));
        final dir = Directory('${local.path}/BeastEmu/saves');
        File saved() => dir.listSync().whereType<File>().singleWhere(
          (f) => f.path.endsWith('.cart'),
        );
        // The first checkpoint must be on disk while the emulator is still alive.
        await session(
          local,
          rom,
          240,
          beforeClose: () async {
            final data = await saved().readAsBytes();
            expect(data[45], 0x51);
            expect(data[46], 1);
          },
        );
        final first = await saved().readAsBytes();
        final layout = ByteData.sublistView(first);
        expect(layout.getUint32(37, Endian.little), 32768);
        expect(layout.getUint32(41, Endian.little), clock ? 32 : 0);
        if (clock) await Future<void>.delayed(const Duration(seconds: 15));
        final renamed = await rom.rename(
          '${local.path}/moved.${clock ? "gbc" : "gb"}',
        );
        // Ends before the 5-second checkpoint; boot count 2 requires final flush.
        await session(local, renamed, 140);
        final second = await saved().readAsBytes();
        expect(second[46], 2);
        if (clock) {
          expect(first[47], inInclusiveRange(17, 20));
          expect((second[47] - first[47] + 60) % 60, greaterThanOrEqualTo(15));
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
      skip:
          !Platform.isWindows ||
          !File('cores/windows/sameboy_libretro.dll').existsSync(),
    );
  }
}
