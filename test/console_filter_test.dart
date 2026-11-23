import 'package:beastemu/services/game_library_service.dart';
import 'package:beastemu/models/game_entry.dart';
import 'package:beastemu/main.dart';
import 'package:beastemu/services/emulation_settings.dart';
import 'package:beastemu/services/keyboard_bindings.dart';
import 'package:beastemu/widgets/game_library_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Library extends Fake implements GameLibraryService {
  @override
  Future<List<GameEntry>> loadGames() async => const [
    GameEntry(
      id: '1',
      title: 'Azul',
      originalName: 'blue.gb',
      localPath: 'unused',
    ),
    GameEntry(
      id: '2',
      title: 'Cor',
      originalName: 'color.gbc',
      localPath: 'unused',
      console: 'Game Boy Color',
    ),
  ];
}

class _ActivityLibrary extends Fake implements GameLibraryService {
  var games = [
    const GameEntry(
      id: 'first',
      title: 'Zeta',
      originalName: 'z.gb',
      localPath: 'fake',
    ),
    GameEntry(
      id: 'second',
      title: 'Alpha',
      originalName: 'a.gb',
      localPath: 'fake',
      favorite: true,
      lastPlayed: DateTime.utc(2026),
    ),
  ];
  @override
  Future<List<GameEntry>> loadGames() async => games;
  @override
  Future<List<GameEntry>> updateEntry(
    GameEntry item,
    List<GameEntry> entries,
  ) async =>
      games = [for (final entry in entries) entry.id == item.id ? item : entry];
}

void main() {
  testWidgets('Link Cable exige duas escolhas e aceita o mesmo cartucho', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GameLibraryView(
              settings: EmulationSettings(),
              bindings: KeyboardBindings(),
              onFilter: (_) {},
              library: _Library(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link Cable Local'));
    await tester.pumpAndSettle();
    final connect = find.widgetWithText(FilledButton, 'Conectar');
    expect(tester.widget<FilledButton>(connect).onPressed, isNull);
    for (final player in [1, 2]) {
      await tester.tap(find.byType(DropdownButton<GameEntry>).at(player - 1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('J$player · Azul (blue.gb)').last);
      await tester.pumpAndSettle();
    }
    expect(tester.widget<FilledButton>(connect).onPressed, isNotNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Jogar'), findsNWidgets(2));
  });
  testWidgets('Continuar jogando abre o histórico real da biblioteca', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BeastHome(
          library: _ActivityLibrary(),
          settings: EmulationSettings(),
          bindings: KeyboardBindings(),
        ),
      ),
    );
    final recent = find.text('Ver jogos recentes');
    await tester.scrollUntilVisible(
      recent,
      260,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(recent);
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Zeta'), findsNothing);
  });
  testWidgets('favoritos e recentes filtram os cards e preservam a coleção', (
    tester,
  ) async {
    final library = _ActivityLibrary();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GameLibraryView(
              settings: EmulationSettings(),
              bindings: KeyboardBindings(),
              onFilter: (_) {},
              library: library,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Jogar'), findsNWidgets(2));
    expect(find.text('Visualizar frame'), findsNothing);
    expect(find.text('Testar controles'), findsNothing);
    await tester.tap(find.byTooltip('Opções do jogo').first);
    await tester.pumpAndSettle();
    expect(find.text('Escolher capa'), findsOneWidget);
    expect(find.text('Visualizar frame'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favoritos'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Zeta'), findsNothing);
    await tester.tap(find.byTooltip('Remover dos favoritos'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhum favorito neste filtro'), findsOneWidget);
    await tester.tap(find.text('Favoritos'));
    await tester.tap(find.text('Título'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recentes').last);
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Zeta'), findsNothing);
    expect(library.games.length, 2);
  });
  test('filtra plataformas e inclui cartuchos de modo duplo', () {
    GameEntry game(String c) => GameEntry(
      id: 'x',
      title: 't',
      originalName: 'r',
      localPath: 'p',
      console: c,
    );
    expect(game('Game Boy Color').matchesConsole('Game Boy'), false);
    expect(game('Game Boy').matchesConsole('Game Boy Color'), false);
    expect(game('GB / GBC').matchesConsole('Game Boy Color'), true);
    expect(game('GB / GBC').matchesConsole('Game Boy'), true);
    expect(game('Game Boy Color').matchesConsole(null), true);
  });
  testWidgets('card de console abre filtro e Todos restaura a visão geral', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BeastHome(
          library: _Library(),
          settings: EmulationSettings(),
          bindings: KeyboardBindings(),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Game Boy Color'));
    await tester.tap(find.text('Game Boy Color'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<GameLibraryView>(find.byType(GameLibraryView))
          .consoleFilter,
      'Game Boy Color',
    );
    expect(find.text('Azul'), findsNothing);
    expect(find.text('Cor'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Todos'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Todos'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<GameLibraryView>(find.byType(GameLibraryView))
          .consoleFilter,
      isNull,
    );
    expect(find.text('Azul'), findsOneWidget);
  });
}
