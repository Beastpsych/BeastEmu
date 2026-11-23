import 'dart:io';
import 'dart:typed_data';

import 'sameboy_launch.dart';

class SameBoyPreview {
  const SameBoyPreview({required this.bmpBytes, required this.log});
  final Uint8List bmpBytes;
  final String log;
}

class SameBoyPreviewService {
  static Future<SameBoyPreview> capture(String romPath) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Prévia disponível apenas no Windows.');
    }
    final rom = File(romPath).absolute;
    if (!await rom.exists()) {
      throw StateError('ROM importada não encontrada: ${rom.path}');
    }
    final ext = rom.path.toLowerCase();
    if (!ext.endsWith('.gb') && !ext.endsWith('.gbc')) {
      throw const FormatException('A prévia aceita somente arquivos GB/GBC.');
    }
    final launch = SameBoyLaunch.resolve(SameBoyHelper.preview);
    final directory = await Directory.systemTemp.createTemp(
      'beastemu-preview-',
    );
    final bmp = File('${directory.path}/frame.bmp');
    try {
      final result = await Process.run(
        launch.executable,
        [...launch.prefix, rom.path, bmp.path],
        workingDirectory: launch.root.path,
        runInShell: launch.usesShell,
      );
      final log = '${result.stdout}\n${result.stderr}'.trim();
      if (result.exitCode != 0) {
        throw StateError(
          'SameBoy terminou com código ${result.exitCode}.\n$log',
        );
      }
      if (!await bmp.exists()) {
        throw StateError('O auxiliar terminou sem gerar a prévia.');
      }
      final bytes = await bmp.readAsBytes();
      if (bytes.length < 54 || bytes[0] != 0x42 || bytes[1] != 0x4d) {
        throw StateError('O arquivo de imagem gerado não é um BMP válido.');
      }
      return SameBoyPreview(bmpBytes: bytes, log: log);
    } finally {
      if (await bmp.exists()) await bmp.delete();
      await directory.delete();
    }
  }
}
