import 'dart:io';

import '../tool/gba_demo.dart';

import 'package:crypto/crypto.dart';

import 'dart:typed_data';

import 'package:beastemu/services/game_library_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Preferences extends Fake implements SharedPreferencesAsync {
  final data = <String, String>{};
  @override
  Future<void> setString(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<String?> getString(String key) async => data[key];
}

final class _Rom extends PlatformFile {
  _Rom(this.name, this.contents);
  @override
  final String name;
  final Uint8List contents;
  @override
  Future<Uint8List> readAsBytes() async => contents;
  @override
  int lengthSync() => contents.length;
  @override
  Future<int> length() async => contents.length;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('importação GBA conserva os registros GB, hash, favorito e extensão na recuperação', () async {
    final dir = await Directory.systemTemp.createTemp('gba-library-');
    addTearDown(() => dir.delete(recursive: true));
    final lib = GameLibraryService(
      romDirectory: dir,
      preferences: _Preferences(),
    );
    final gb = await lib.importGameBoyFiles([
      _Rom('old.gbc', Uint8List(32768)..[0x143] = 0x80),
    ], []);
    final data = gbaDemo();
    final source = _Rom('demo.GBA', data);
    final result = await lib.importGameBoyFiles([
      source,
      _Rom('duplicate.gba', data),
      _Rom('bad.gba', Uint8List(400)),
    ], gb.games);
    expect((result.added, result.duplicates, result.skipped), (1, 1, 1));
    expect(result.games.first.toJson(), gb.games.single.toJson());
    expect(result.games.first.matchesConsole('Game Boy Advance'), false);
    final game = result.games.last;
    expect(game.matchesConsole('Game Boy Advance'), true);
    expect(game.romHash, sha256.convert(data).toString());
    final games = await lib.updateEntry(
      game.copyWith(favorite: true),
      result.games,
    );
    await File(game.localPath).delete();
    final recovered = await lib.recover(games.last, games, source);
    expect(recovered.last.localPath, endsWith('.gba'));
    expect((await lib.loadGames()).last.favorite, true);
    expect(await File(recovered.last.localPath).readAsBytes(), data);
  });
  test(
    'conteúdo distingue nomes iguais e reconhece a mesma ROM renomeada',
    () async {
      final folder = await Directory.systemTemp.createTemp('beast-import-');
      addTearDown(() => folder.delete(recursive: true));
      final library = GameLibraryService(
        romDirectory: folder,
        preferences: _Preferences(),
      );
      final bytes = Uint8List(32768)..setAll(0x134, 'TEST'.codeUnits);
      final result = await library.importGameBoyFiles([
        _Rom('game.gb', bytes),
        _Rom('game.gb', Uint8List.fromList(bytes)..[0] = 1),
        _Rom('renamed.gb', bytes),
      ], []);
      expect(result.added, 2);
      expect(result.duplicates, 1);
      expect(result.games.map((g) => g.romHash).toSet(), hasLength(2));
    },
  );
  test(
    'favorito, execução e identidade sobrevivem à recuperação da cópia',
    () async {
      final folder = await Directory.systemTemp.createTemp('beast-library-');
      addTearDown(() => folder.delete(recursive: true));
      final prefs = _Preferences();
      final library = GameLibraryService(
        romDirectory: folder,
        preferences: prefs,
      );
      final bytes = Uint8List(32768)..setAll(0x134, 'TEST'.codeUnits);
      final source = _Rom('original.gb', bytes);
      final imported = await library.importGameBoyFiles([source], []);
      final stamp = DateTime.utc(2026, 1, 2);
      final updated = await library.updateEntry(
        imported.games.single.copyWith(favorite: true, lastPlayed: stamp),
        imported.games,
      );
      // Move only the synthetic copy owned by this test.
      final game = updated.single;
      final moved = await File(game.localPath)
          .rename('${folder.path}/moved.gb');
      final other = _Rom('original.gb', Uint8List.fromList(bytes)..[0] = 1);
      await expectLater(
        library.recover(game, updated, other),
        throwsFormatException,
      );
      final fresh = GameLibraryService(
        romDirectory: folder,
        preferences: prefs,
      );
      final disk = await fresh.loadGames();
      expect(disk.single.favorite, true);
      expect(disk.single.lastPlayed, stamp);
      final recovered = (await fresh.recover(disk.single, disk, source)).single;
      expect(recovered.id, game.id);
      expect(recovered.romHash, game.romHash);
      expect(await moved.readAsBytes(), bytes);
      expect(await File(recovered.localPath).readAsBytes(), bytes);
      expect((await fresh.loadGames()).single.localPath, recovered.localPath);
    },
  );
}
