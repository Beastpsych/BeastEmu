import 'dart:io';

import 'package:beastemu/services/game_cover_store.dart';
import 'package:beastemu/widgets/game_cover.dart';
import 'package:beastemu/services/keyboard_bindings.dart';
import 'package:beastemu/services/gamepads.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:beastemu/widgets/beast_brand.dart';

import 'package:beastemu/core/theme.dart';
import 'package:beastemu/models/game_entry.dart';
import 'package:beastemu/services/emulation_settings.dart';
import 'package:beastemu/services/game_library_service.dart';
import 'package:beastemu/widgets/sameboy_live_dialog.dart';

class GameLibraryView extends StatefulWidget {
  const GameLibraryView({
    super.key,
    required this.settings,
    required this.bindings,
    this.consoleFilter,
    this.recent = false,
    required this.onFilter,
    this.library,
    this.gamepads,
  });
  final GameLibraryService? library;
  final Gamepads? gamepads;
  final String? consoleFilter;
  final bool recent;
  final ValueChanged<String?> onFilter;

  final EmulationSettings settings;
  final KeyboardBindings bindings;

  @override
  State<GameLibraryView> createState() => _GameLibraryViewState();
}

class _GameLibraryViewState extends State<GameLibraryView> {
  late final _service = widget.library ?? GameLibraryService();
  final _covers = GameCoverStore();
  final _coverRevisions = <String, int>{};
  List<GameEntry> _games = [];
  bool _loading = true;
  bool _busy = false;
  bool _checkingFile = false;
  bool _favoritesOnly = false;
  late String _order = widget.recent ? 'Recentes' : 'Título';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    try {
      final games = await _service.loadGames();
      if (!mounted) return;
      setState(() {
        _games = games;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível carregar a biblioteca: $error';
        _loading = false;
      });
    }
  }

  Future<void> _importGames() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gb', 'gbc'],
        dialogTitle: 'Selecionar jogos GB/GBC (.gb, .gbc)',
      );
      if (files.isEmpty) return; // Janela cancelada.

      final result = await _service.importGameBoyFiles(files, _games);
      if (!mounted) return;
      setState(() {
        _games = result.games;
        _error = null;
      });

      final message = result.added == 0
          ? 'Nenhum jogo novo importado.'
          : '${result.added} jogo(s) adicionado(s) à biblioteca.';
      final extras = result.duplicates + result.skipped;
      _notify(extras > 0 ? '$message $extras ignorado(s).' : message);
    } catch (error) {
      if (mounted) _notify('Erro ao importar: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(GameEntry game) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover da biblioteca?'),
        content: Text(
          'Remover "${game.title}"? Apenas a cópia interna do BeastEmu '
          'será apagada. Seu arquivo original não será alterado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final remaining = await _service.removeGame(game, _games);
      if (!mounted) return;
      setState(() => _games = remaining);
      _notify('Jogo removido da biblioteca.');
    } catch (error) {
      if (mounted) _notify('Erro ao remover: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateEntry(GameEntry game) async {
    setState(() => _busy = true);
    try {
      final entries = await _service.updateEntry(game, _games);
      if (mounted) setState(() => _games = entries);
    } catch (error) {
      if (mounted) _notify('Falha ao atualizar a biblioteca: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _available(GameEntry game) async {
    if (_checkingFile) return false;
    _checkingFile = true;
    try {
      return await _checkOrRecover(game);
    } catch (error) {
      if (mounted) _notify('Falha ao verificar a ROM: $error');
      return false;
    } finally {
      _checkingFile = false;
    }
  }

  Future<bool> _checkOrRecover(GameEntry game) async {
    if (await File(game.localPath).exists()) return true;
    if (!mounted) return false;
    final locate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cópia da ROM ausente'),
        content: Text(
          game.romHash == null
              ? 'Esta entrada antiga não possui hash. Selecione o arquivo original com o mesmo nome e edição para recuperar a cópia de ${game.title}.'
              : 'Selecione a ROM de ${game.title}. O BeastEmu verificará o conteúdo e recuperará a cópia da biblioteca.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Localizar ROM'),
          ),
        ],
      ),
    );
    if (locate != true || !mounted) return false;
    setState(() => _busy = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gb', 'gbc'],
      );
      if (files.isEmpty) return false;
      final entries = await _service.recover(game, _games, files.single);
      if (mounted) {
        setState(() => _games = entries);
        _notify('Cópia recuperada. O jogo está disponível.');
      }
    } catch (error) {
      if (mounted) _notify('Falha ao recuperar a ROM: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return false;
  }

  Future<void> _play(GameEntry game) async {
    if (!await _available(game) || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SameBoyLiveDialog(
        gamepads: widget.gamepads,
        settings: widget.settings,
        bindings: widget.bindings,
        romPath: game.localPath,
        expectedRomHash: game.romHash,
        gameTitle: game.title,
        onFirstFrame: () =>
            _updateEntry(game.copyWith(lastPlayed: DateTime.now().toUtc())),
      ),
    );
  }

  Future<void> _linkLocal() async {
    final selected = <GameEntry?>[null, null];
    final start = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Link Cable Local · Experimental'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < 2; i++)
                    DropdownButton<GameEntry>(
                      isExpanded: true,
                      value: selected[i],
                      hint: Text('Selecionar ROM do jogador ${i + 1}'),
                      items: [
                        for (final game in _games)
                          DropdownMenuItem(
                            value: game,
                            child: Text(
                              'J${i + 1} · ${game.title} (${game.originalName})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => refresh(() => selected[i] = value),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'O teclado controla o jogador 1. Com um controle Xbox, ele joga como jogador 2. Com dois controles, eles seguem a ordem XInput.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Cada jogador usa seu próprio save do Link Cable. O áudio vem do jogador 1.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: selected.contains(null)
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Conectar'),
            ),
          ],
        ),
      ),
    );
    if (start != true || !mounted) return;
    final first = selected[0]!;
    final second = selected[1]!;
    if (!await _available(first) ||
        !mounted ||
        !await _available(second) ||
        !mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SameBoyLiveDialog(
        settings: widget.settings,
        bindings: widget.bindings,
        gamepads: widget.gamepads,
        romPath: first.localPath,
        gameTitle: first.title,
        partner: (path: second.localPath, title: second.title),
      ),
    );
  }

  Future<void> _chooseCover(GameEntry game) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        dialogTitle: 'Escolher capa',
      );
      if (files.isEmpty) return;
      final source = files.single;
      if ((await source.length() ?? 0) > 16 * 1024 * 1024) {
        throw const FormatException('Escolha uma imagem de até 16 MB.');
      }
      final file = await _covers.set(game.id, await source.readAsBytes());
      await FileImage(file).evict();
      if (mounted) {
        setState(
          () =>
              _coverRevisions.update(game.id, (n) => n + 1, ifAbsent: () => 1),
        );
      }
    } catch (error) {
      if (mounted) _notify('Não foi possível usar a capa: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final games =
        _games
            .where((g) => g.matchesConsole(widget.consoleFilter))
            .where((g) => !_favoritesOnly || g.favorite)
            .where((g) => _order != 'Recentes' || g.lastPlayed != null)
            .toList()
          ..sort((a, b) {
            if (_order == 'Recentes') {
              final compare = b.lastPlayed!.compareTo(a.lastPlayed!);
              if (compare != 0) return compare;
            }
            if (_order == 'Console') {
              final compare = a.console.compareTo(b.console);
              if (compare != 0) return compare;
            }
            final compare = a.title.toLowerCase().compareTo(
              b.title.toLowerCase(),
            );
            return compare != 0 ? compare : a.id.compareTo(b.id);
          });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final console in <String?>[null, 'Game Boy', 'Game Boy Color'])
              ChoiceChip(
                label: Text(console ?? 'Todos'),
                selected: widget.consoleFilter == console,
                onSelected: (_) => widget.onFilter(console),
              ),
            FilterChip(
              label: const Text('Favoritos'),
              selected: _favoritesOnly,
              onSelected: (on) => setState(() => _favoritesOnly = on),
            ),
            DropdownButton<String>(
              value: _order,
              items: [
                for (final label in ['Título', 'Console', 'Recentes'])
                  DropdownMenuItem(value: label, child: Text(label)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _order = value);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Text(
              '${games.length} jogo(s)',
              style: const TextStyle(color: Colors.grey),
            ),
            FilledButton.icon(
              onPressed: _loading || _busy ? null : _importGames,
              style: FilledButton.styleFrom(backgroundColor: beastRed),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar jogos GB/GBC'),
            ),
            OutlinedButton.icon(
              onPressed: _loading || _busy || _games.isEmpty
                  ? null
                  : _linkLocal,
              icon: const Icon(Icons.cable),
              label: const Text('Link Cable Local'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _loadLibrary,
            child: const Text('Tentar novamente'),
          ),
        ],
        if (!_loading && _error == null && games.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
              color: beastPanel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                const BeastBrand(BeastArtwork.compact, width: 100, height: 70),
                SizedBox(height: 12),
                Text(
                  _favoritesOnly
                      ? 'Nenhum favorito neste filtro'
                      : _order == 'Recentes'
                      ? 'Nenhum jogo executado neste filtro'
                      : widget.consoleFilter == null
                      ? 'Sua biblioteca está vazia'
                      : 'Nenhum jogo de ${widget.consoleFilter}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Adicione arquivos .gb ou .gbc que você tem permissão para usar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        if (!_loading && _error == null && games.isNotEmpty) ...[
          LayoutBuilder(
            builder: (context, bounds) {
              final count = ((bounds.maxWidth + 14) / 214).floor().clamp(1, 8);
              final width = (bounds.maxWidth - 14 * (count - 1)) / count;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final game in games)
                    SizedBox(width: width, child: _gameCard(game)),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _gameCard(GameEntry game) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: beastPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.videogame_asset_outlined,
                color: Colors.redAccent,
                size: 30,
              ),
              const Spacer(),
              IconButton(
                tooltip: game.favorite
                    ? 'Remover dos favoritos'
                    : 'Adicionar aos favoritos',
                onPressed: _busy
                    ? null
                    : () =>
                          _updateEntry(game.copyWith(favorite: !game.favorite)),
                icon: Icon(
                  game.favorite ? Icons.star : Icons.star_outline,
                  color: game.favorite ? beastRed : null,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opções do jogo',
                enabled: !_busy,
                onSelected: (value) {
                  if (value == 'cover') _chooseCover(game);
                  if (value == 'remove') _remove(game);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'cover', child: Text('Escolher capa')),
                  PopupMenuItem(value: 'remove', child: Text('Remover')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          GameCover(
            key: ValueKey((game.id, _coverRevisions[game.id])),
            id: game.id,
            store: _covers,
          ),
          const SizedBox(height: 10),
          Text(
            game.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            '${game.console}  •  ${game.originalName.toLowerCase().endsWith('.gbc') ? '.gbc' : '.gb'}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (game.lastPlayed case final played?)
            Text(
              'Última execução: ${MaterialLocalizations.of(context).formatCompactDate(played.toLocal())} '
              '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(played.toLocal()))}',
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _play(game),
            style: FilledButton.styleFrom(backgroundColor: beastRed),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Jogar'),
          ),
        ],
      ),
    );
  }
}
