/// The Windows development build accepts raw cartridges up to 32 MiB.
const mgbaCoreHash =
    'aad5891c91611c226a864e3d308e791038c862ca7e3a06491e6aa2b11bbc792f';

enum CartridgeCore { sameBoy, mgba }

CartridgeCore? coreForPath(String path) {
  final name = path.toLowerCase();
  if (name.endsWith('.gba')) return CartridgeCore.mgba;
  if (name.endsWith('.gb') || name.endsWith('.gbc')) {
    return CartridgeCore.sameBoy;
  }
  return null;
}

String gbaTitle(List<int> bytes) {
  // mGBA also accepts unfixed homebrew headers with an empty logo region.
  if (bytes.length < 0xc0 ||
      bytes.length > 32 * 1024 * 1024 ||
      bytes[3] != 0xea ||
      (bytes[0xb2] != 0x96 && bytes.getRange(4, 0xa0).any((b) => b != 0))) {
    throw const FormatException('Cabeçalho GBA inválido.');
  }
  final title = String.fromCharCodes(
    bytes
        .getRange(0xa0, 0xac)
        .takeWhile((b) => b != 0)
        .where((b) => b >= 32 && b <= 126),
  ).trim();
  return title.isEmpty ? 'Sem titulo' : title;
}
