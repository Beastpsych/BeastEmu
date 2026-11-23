import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:beastemu/services/windows_profile.dart';

class GameCoverStore {
  GameCoverStore({this.directory});
  final Directory? directory;
  Future<File> fileFor(String id) async {
    final dir = directory ?? await gameDataDirectory();
    return File('${dir.path}/covers/${sha256.convert(utf8.encode(id))}.png');
  }

  Future<File?> find(String id) async {
    final file = await fileFor(id);
    return await file.exists() ? file : null;
  }

  Future<File> set(String id, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) {
      throw const FormatException('Escolha uma imagem de até 16 MB.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    late final ByteData png;
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width * descriptor.height > 24000000) {
          throw const FormatException('A imagem excede 24 megapixels.');
        }
        final ratio = math.min(
          1.0,
          512 / math.max(descriptor.width, descriptor.height),
        );
        final codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * ratio).round()),
          targetHeight: math.max(1, (descriptor.height * ratio).round()),
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            png = (await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
    final file = await fileFor(id);
    await file.parent.create(recursive: true);
    final tmp = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tmp.create(exclusive: true);
    try {
      await tmp.writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        flush: true,
      );
      await tmp.rename(file.path);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
    return file;
  }
}
