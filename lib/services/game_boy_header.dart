import 'dart:io';

/// Informações básicas extraídas do cabeçalho do cartucho GB/GBC.
class GameBoyCartridge {
  const GameBoyCartridge({
    required this.title,
    required this.console,
    required this.cgbFlag,
  });

  final String title;
  final String console;
  final int cgbFlag;

  String get libraryConsole {
    if (cgbFlag == 0xC0) return 'Game Boy Color';
    if (cgbFlag == 0x80) return 'GB / GBC';
    return 'Game Boy';
  }
}

class GameBoyHeaderReader {
  /// Lê somente o cabeçalho, sem carregar a ROM inteira em memória.
  static Future<GameBoyCartridge> read(String path) async {
    final reader = await File(path).open(mode: FileMode.read);
    try {
      final bytes = await reader.read(0x150);
      return fromBytes(bytes);
    } finally {
      await reader.close();
    }
  }

  /// Permite analisar bytes que já foram lidos na importação.
  static GameBoyCartridge fromBytes(List<int> bytes) {
    if (bytes.length < 0x150) {
      throw const FormatException('Arquivo muito pequeno para uma ROM GB/GBC.');
    }

    // $0143: 0x80 = compatível GB/GBC; 0xC0 = exclusivo GBC.
    final flag = bytes[0x143];
    final cgb = flag == 0x80 || flag == 0xC0;
    final console = flag == 0xC0
        ? 'Game Boy Color (exclusivo)'
        : flag == 0x80
            ? 'Game Boy Color (compativel com GB)'
            : 'Game Boy';

    // Em cartuchos CGB, $0143 pertence à flag, e não ao título.
    final titleEnd = cgb ? 0x143 : 0x144;
    final titleBytes = bytes
        .sublist(0x134, titleEnd)
        .takeWhile((value) => value != 0)
        .where((value) => value >= 32 && value <= 126);
    final title = String.fromCharCodes(titleBytes).trim();

    return GameBoyCartridge(
      title: title.isEmpty ? 'Sem titulo' : title,
      console: console,
      cgbFlag: flag,
    );
  }
}
