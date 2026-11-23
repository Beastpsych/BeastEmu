import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:file_picker/file_picker.dart';
import 'package:beastemu/services/windows_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beastemu/models/game_entry.dart';
import 'package:beastemu/services/game_boy_header.dart';

class ImportSummary {
  const ImportSummary({
    required this.games,
    required this.added,
    required this.duplicates,
    required this.skipped,
  });

  final List<GameEntry> games;
  final int added;
  final int duplicates;
  final int skipped;
}

/// Guarda cópias selecionadas pelo usuário em pasta privada do aplicativo.
/// A identidade da entrada e as preferências acompanham a cópia privada.
class GameLibraryService {
  // Mesma chave da etapa 03: preserva a coleção já importada.
  static const _storageKey = 'beastemu.gameboy.library.v1';
  static const _maxRomBytes = 32 * 1024 * 1024;

  GameLibraryService({SharedPreferencesAsync? preferences, this.romDirectory})
    : _preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync _preferences;
  final Directory? romDirectory;

  Future<List<GameEntry>> loadGames() async {
    final raw = await _preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    final entries = jsonDecode(raw) as List<dynamic>;
    final games = <GameEntry>[];
    var migrated = false;

    for (final rawEntry in entries) {
      final json = Map<String, dynamic>.from(rawEntry as Map);
      var game = GameEntry.fromJson(json);

      // Atualiza ROMs que foram importadas na etapa anterior.
      // Se o arquivo não existir, preserva o registro anterior.
      if (!json.containsKey('console')) {
        try {
          final cartridge = await GameBoyHeaderReader.read(game.localPath);
          game = game.copyWith(
            title: cartridge.title == 'Sem titulo'
                ? game.title
                : cartridge.title,
            console: cartridge.libraryConsole,
          );
          migrated = true;
        } on FileSystemException {
          // Não apagamos automaticamente registros de jogos ausentes.
        } on FormatException {
          // Preservamos nomes antigos quando não for possível ler cabeçalho.
        }
      }
      games.add(game);
    }

    if (migrated) await _saveGames(games);
    return games;
  }

  Future<void> _saveGames(List<GameEntry> games) async {
    await _preferences.setString(
      _storageKey,
      jsonEncode(games.map((game) => game.toJson()).toList()),
    );
  }

  Future<ImportSummary> importGameBoyFiles(
    List<PlatformFile> files,
    List<GameEntry> existing,
  ) async {
    final games = List<GameEntry>.from(existing);
    final directory = await _romDirectory();
    final knownHashes = games.map((g) => g.romHash).whereType<String>().toSet();
    var added = 0;
    var duplicates = 0;
    var skipped = 0;

    for (final file in files) {
      final fileName = file.name.trim();
      final lowerName = fileName.toLowerCase();
      final extension = lowerName.endsWith('.gbc')
          ? '.gbc'
          : lowerName.endsWith('.gb')
          ? '.gb'
          : null;

      if (extension == null) {
        skipped++;
        continue;
      }

      try {
        final fileSize = file.lengthSync() ?? await file.length();
        if (fileSize != null && (fileSize < 0x150 || fileSize > _maxRomBytes)) {
          skipped++;
          continue;
        }

        final bytes = await file.readAsBytes();
        if (bytes.length < 0x150 || bytes.length > _maxRomBytes) {
          skipped++;
          continue;
        }

        final cartridge = GameBoyHeaderReader.fromBytes(bytes);
        final hash = sha256.convert(bytes).toString();
        if (knownHashes.contains(hash)) {
          duplicates++;
          continue;
        }
        final id = '${DateTime.now().microsecondsSinceEpoch}_$added';
        final destination = File(
          '${directory.path}${Platform.pathSeparator}$id$extension',
        );
        await destination.writeAsBytes(bytes, flush: true);

        // Nome interno, caso esteja preenchido; senão, nome do arquivo.
        final fallbackTitle = fileName
            .substring(0, fileName.length - extension.length)
            .replaceAll('_', ' ')
            .trim();
        final title = cartridge.title == 'Sem titulo'
            ? (fallbackTitle.isEmpty ? 'Jogo sem título' : fallbackTitle)
            : cartridge.title;

        games.add(
          GameEntry(
            id: id,
            title: title,
            originalName: fileName,
            localPath: destination.path,
            console: cartridge.libraryConsole,
            romHash: hash,
          ),
        );
        knownHashes.add(hash);
        added++;
      } on FormatException {
        skipped++;
      } on FileSystemException {
        skipped++;
      }
    }

    if (added > 0) await _saveGames(games);
    return ImportSummary(
      games: games,
      added: added,
      duplicates: duplicates,
      skipped: skipped,
    );
  }

  Future<List<GameEntry>> updateEntry(
    GameEntry replacement,
    List<GameEntry> entries,
  ) async {
    final updated = [
      for (final entry in entries)
        entry.id == replacement.id ? replacement : entry,
    ];
    await _saveGames(updated);
    return updated;
  }

  Future<List<GameEntry>> recover(
    GameEntry game,
    List<GameEntry> entries,
    PlatformFile source,
  ) async {
    if (await File(game.localPath).exists()) {
      throw StateError('A cópia atual está disponível.');
    }
    final length = await source.length();
    if (length != null && (length < 0x150 || length > _maxRomBytes)) {
      throw const FormatException('Tamanho de ROM inválido.');
    }
    final bytes = await source.readAsBytes();
    if (bytes.length < 0x150 || bytes.length > _maxRomBytes) {
      throw const FormatException('Tamanho de ROM inválido.');
    }
    final hash = sha256.convert(bytes).toString();
    if (game.romHash != null) {
      if (hash != game.romHash) {
        throw const FormatException(
          'A ROM selecionada é diferente da importada.',
        );
      }
    } else if (source.name.toLowerCase() != game.originalName.toLowerCase() ||
        GameBoyHeaderReader.fromBytes(bytes).libraryConsole != game.console) {
      throw const FormatException(
        'Escolha o arquivo original desta entrada antiga.',
      );
    }
    final root = await _romDirectory();
    final folder = await root.createTemp('recovered-');
    final file = File(
      '${folder.path}/game.${game.originalName.toLowerCase().endsWith(".gbc") ? "gbc" : "gb"}',
    );
    try {
      await file.writeAsBytes(bytes, flush: true);
      return await updateEntry(
        game.copyWith(localPath: file.path, romHash: hash),
        entries,
      );
    } catch (_) {
      if (await file.exists()) await file.delete();
      await folder.delete();
      rethrow;
    }
  }

  Future<List<GameEntry>> removeGame(
    GameEntry game,
    List<GameEntry> existing,
  ) async {
    final remaining = existing.where((g) => g.id != game.id).toList();
    await _saveGames(remaining);

    // Nunca apaga o arquivo original selecionado pelo usuário.
    final directory = await _romDirectory();
    final privatePrefix = '${directory.absolute.path}${Platform.pathSeparator}';
    final localFile = File(game.localPath).absolute;
    if (localFile.path.startsWith(privatePrefix) && await localFile.exists()) {
      await localFile.delete();
    }
    return remaining;
  }

  Future<Directory> _romDirectory() async {
    if (romDirectory != null) return romDirectory!.create(recursive: true);
    final supportDirectory = await gameDataDirectory();
    return Directory(
      '${supportDirectory.path}${Platform.pathSeparator}beastemu_roms',
    ).create(recursive: true);
  }
}
