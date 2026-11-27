import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beastemu/services/gba_cartridge.dart';
import 'package:crypto/crypto.dart';

/// Read-only inventory. The caller copies only validated files, after backup
/// and explicit conflict resolution. The source is never written or locked.
Future<Map<String, String>> auditGbaImport(
  Directory root,
  Uint8List rom,
) async {
  gbaTitle(rom);
  final id = sha256.convert(rom).toString();
  final files = <String, String>{};
  const sizes = {512, 8192, 32768, 65536, 131072};
  Future<Uint8List> read(String path, int max) async {
    final file = File('${root.path}/$path');
    final n = await file.length();
    if (n < 1 || n > max) throw FormatException('Tamanho inválido: $path');
    final bytes = await file.readAsBytes();
    if (bytes.length != n) {
      throw FormatException('Arquivo mudou durante a leitura: $path');
    }
    files[path] = sha256.convert(bytes).toString();
    return bytes;
  }

  final index = 'saves/mgba/$id/cart.json';
  if (await File('${root.path}/$index').exists()) {
    final meta = jsonDecode(utf8.decode(await read(index, 1024))) as Map;
    final check = sha256
        .convert(
          utf8.encode(jsonEncode([1, id, meta['current'], meta['previous']])),
        )
        .toString();
    if (meta['version'] != 1 ||
        meta['rom'] != id ||
        meta['checksum'] != check ||
        (meta['current'] != null && meta['current'] is! String) ||
        (meta['previous'] != null && meta['previous'] is! String)) {
      throw const FormatException('Índice incompatível.');
    }
    for (final hash in {
      meta['current'],
      meta['previous'],
    }.whereType<String>()) {
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
        throw const FormatException('Hash inválido.');
      }
      final bytes = await read('saves/mgba/$id/$hash.sav', 131072);
      if (!sizes.contains(bytes.length) ||
          sha256.convert(bytes).toString() != hash) {
        throw const FormatException('Imagem de cartucho inválida.');
      }
    }
  }
  final romDigest = sha256.convert(rom).bytes;
  final core = List<int>.generate(
    32,
    (i) => int.parse(mgbaCoreHash.substring(i * 2, i * 2 + 2), radix: 16),
  );
  final version = sha256
      .convert(utf8.encode('mGBA\u00000.11-212-7a12d6d'))
      .bytes;
  for (var slot = 0; slot <= 5; slot++) {
    final path = 'states/mgba/$id/${slot == 0 ? 'quick' : slot}.state';
    if (!await File('${root.path}/$path').exists()) continue;
    final bytes = await read(path, 34 * 1024 * 1024);
    if (bytes.length < 150) throw const FormatException('Estado truncado.');
    final header = ByteData.sublistView(bytes);
    final n = header.getUint32(110, Endian.little),
        ram = header.getUint32(114, Endian.little);
    final identity = [
      ...'BGA1'.codeUnits,
      1,
      ...romDigest,
      ...core,
      ...version,
      slot,
    ];
    final identityMatches = List.generate(
      identity.length,
      (i) => bytes[i] == identity[i],
    ).every((v) => v);
    final checksum = sha256
        .convert(bytes.sublist(0, bytes.length - 32))
        .toString();
    if (!identityMatches ||
        n < 1 ||
        n > 32 * 1024 * 1024 ||
        !{0, ...sizes}.contains(ram) ||
        bytes.length != 118 + n + ram + 32 ||
        checksum != Digest(bytes.sublist(bytes.length - 32)).toString()) {
      throw FormatException('Estado incompatível ou corrompido: $path');
    }
  }
  if (files.isEmpty) {
    throw const FormatException('Nenhum dado GBA encontrado para esta ROM.');
  }
  return files;
}

Future<void> main(List<String> args) async {
  try {
    if (args.length != 3) {
      throw const FormatException(
        'Uso: dart run tool/audit_gba_import.dart <ROM.gba> <raiz-origem-BeastEmu> <raiz-destino-BeastEmu>',
      );
    }
    final rom = File(args[0]);
    if (await rom.length() > 32 * 1024 * 1024) {
      throw const FormatException('ROM grande demais.');
    }
    final entries = await auditGbaImport(
      Directory(args[1]),
      await rom.readAsBytes(),
    );
    for (final entry in entries.entries) {
      final exists = await File('${args[2]}/${entry.key}').exists();
      stdout.writeln(
        '${exists ? 'CONFLITO' : 'NOVO'} ${entry.key} ${entry.value}',
      );
    }
    stdout.writeln(
      'Auditoria somente leitura concluída. Faça backup e resolva cada conflito antes da cópia manual.',
    );
  } catch (error) {
    stderr.writeln('Importação recusada: $error');
    exitCode = 1;
  }
}
