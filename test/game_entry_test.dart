import 'package:flutter_test/flutter_test.dart';
import 'package:beastemu/models/game_entry.dart';

void main() {
  test('GameEntry grava e recupera console no JSON', () {
    const game = GameEntry(
      id: '123',
      title: 'Meu jogo',
      originalName: 'meu_jogo.gbc',
      localPath: r'C:\BeastEmu\123.gbc',
      console: 'Game Boy Color',
    );
    final restored = GameEntry.fromJson(game.toJson());
    expect(restored.id, game.id);
    expect(restored.title, game.title);
    expect(restored.originalName, game.originalName);
    expect(restored.localPath, game.localPath);
    expect(restored.console, 'Game Boy Color');
  });

  test('GameEntry lê formato antigo sem campo console', () {
    final legacy = <String, dynamic>{
      'id': 'old',
      'title': 'Jogo antigo',
      'originalName': 'jogo.gb',
      'localPath': r'C:\BeastEmu\jogo.gb',
    };
    expect(GameEntry.fromJson(legacy).console, 'Game Boy');
  });
}
