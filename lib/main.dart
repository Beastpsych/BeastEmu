import 'package:beastemu/services/game_library_service.dart';
import 'package:beastemu/services/windows_profile.dart';
import 'package:beastemu/services/keyboard_bindings.dart';
import 'package:beastemu/services/gamepads.dart';
import 'package:beastemu/widgets/gamepad_settings_panel.dart';
import 'package:beastemu/widgets/keyboard_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:beastemu/core/theme.dart';
import 'package:beastemu/core/version.dart';
import 'package:beastemu/widgets/beast_brand.dart';
import 'package:beastemu/widgets/beast_sidebar.dart';
import 'package:beastemu/widgets/game_library_view.dart';

import 'package:beastemu/services/emulation_settings.dart';
import 'package:beastemu/widgets/emulation_settings_panel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeWindowsProfile();
  } catch (error) {
    debugPrint('Preparação do perfil BeastEmu: $error');
    runApp(
      MaterialApp(
        title: 'BeastEmu',
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: SelectableText(
                'Não foi possível abrir o perfil BeastEmu. '
                'Confira o acesso à pasta de dados e o arquivo shared_preferences.json '
                'do perfil anterior. Feche o aplicativo e tente novamente.',
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  final settings = EmulationSettings();
  final bindings = KeyboardBindings();
  final gamepads = Gamepads();
  await Future.wait([settings.load(), bindings.load(), gamepads.load()]);
  runApp(
    BeastEmuApp(settings: settings, bindings: bindings, gamepads: gamepads),
  );
}

/// Interface Beast Edition.
class BeastEmuApp extends StatelessWidget {
  const BeastEmuApp({
    super.key,
    required this.settings,
    required this.bindings,
    this.gamepads,
  });

  final EmulationSettings settings;
  final KeyboardBindings bindings;
  final Gamepads? gamepads;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BeastEmu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: beastBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: beastRed,
          brightness: Brightness.dark,
        ),
      ),
      home: BeastHome(
        settings: settings,
        bindings: bindings,
        gamepads: gamepads,
      ),
    );
  }
}

class BeastHome extends StatefulWidget {
  const BeastHome({
    super.key,
    required this.settings,
    required this.bindings,
    this.library,
    this.gamepads,
  });
  final GameLibraryService? library;
  final Gamepads? gamepads;

  final EmulationSettings settings;
  final KeyboardBindings bindings;

  @override
  State<BeastHome> createState() => _BeastHomeState();
}

class _BeastHomeState extends State<BeastHome> {
  int selectedPage = 0;
  bool showRecentGames = false;
  String? consoleFilter;
  void openConsole(String console) {
    setState(() {
      consoleFilter = console;
      showRecentGames = false;
      selectedPage = 1;
    });
  }

  static const List<String> pages = [
    'Início',
    'Biblioteca',
    'Consoles',
    'Configurações',
  ];

  static const List<IconData> icons = [
    Icons.home_outlined,
    Icons.library_books_outlined,
    Icons.sports_esports_outlined,
    Icons.settings_outlined,
  ];

  void navigate(int index, {bool recent = false}) {
    setState(() {
      selectedPage = index;
      consoleFilter = null;
      showRecentGames = recent;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 800;

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (desktop)
                  BeastSidebar(
                    pages: pages,
                    icons: icons,
                    selectedPage: selectedPage,
                    onPageSelected: navigate,
                  ),
                Expanded(child: buildContent()),
              ],
            ),
          ),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  backgroundColor: beastPanel,
                  selectedIndex: selectedPage,
                  onDestinationSelected: navigate,
                  destinations: List.generate(
                    pages.length,
                    (index) => NavigationDestination(
                      icon: Icon(icons[index]),
                      label: pages[index],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget buildContent() {
    return ListView(
      key: PageStorageKey(selectedPage),
      padding: const EdgeInsets.all(28),
      children: [
        Row(
          children: [
            if (MediaQuery.sizeOf(context).width < 800 &&
                selectedPage != 0) ...[
              const BeastBrand(BeastArtwork.symbol, width: 30, height: 30),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                pages[selectedPage],
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (selectedPage == 3)
              IconButton(
                tooltip: 'Sobre o BeastEmu',
                icon: const Icon(Icons.info_outline),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: beastPanel,
                    scrollable: true,
                    title: const Text('Sobre o BeastEmu'),
                    content: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BeastBrand(
                          BeastArtwork.emblem,
                          height: 152,
                          label: 'Emblema dracônico da Beast Edition',
                        ),
                        SizedBox(height: 16),
                        Text('Versão $beastEmuVersion'),
                        Text('Copyright (c) 2026 Beast'),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Fechar'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (selectedPage == 0) ...[
          buildBanner(),
          const SizedBox(height: 32),
          sectionTitle('Consoles'),
          const SizedBox(height: 16),
          buildConsoles(),
          const SizedBox(height: 32),
          sectionTitle('Continuar jogando'),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => navigate(1, recent: true),
              icon: const Icon(Icons.history),
              label: const Text('Ver jogos recentes'),
            ),
          ),
        ],
        if (selectedPage == 1)
          GameLibraryView(
            library: widget.library,
            recent: showRecentGames,
            consoleFilter: consoleFilter,
            onFilter: (value) => setState(() => consoleFilter = value),
            settings: widget.settings,
            bindings: widget.bindings,
            gamepads: widget.gamepads,
          ),
        if (selectedPage == 2) ...[
          const Text(
            'Plataformas previstas para o BeastEmu',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          buildConsoles(),
        ],
        if (selectedPage == 3) ...[
          EmulationSettingsPanel(settings: widget.settings),
          const SizedBox(height: 16),
          KeyboardSettingsPanel(bindings: widget.bindings),
          if (widget.gamepads case final pads?) ...[
            const SizedBox(height: 16),
            GamepadSettingsPanel(pads: pads),
          ],
        ],
      ],
    );
  }

  Widget buildBanner() {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [beastPanel, Color(0xFF381216), Color(0xFF65151D)],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (MediaQuery.sizeOf(context).width < 800) ...[
                  const BeastBrand(
                    BeastArtwork.horizontal,
                    width: 220,
                    label: 'BeastEmu',
                  ),
                  const SizedBox(height: 16),
                ],
                const Text(
                  'Todos os seus jogos.\nUm só lugar.',
                  style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                const Text('O futuro da sua coleção começa aqui.'),
                const SizedBox(height: 22),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: beastRed,
                  ),
                  onPressed: () => navigate(1),
                  icon: const Icon(Icons.library_books),
                  label: const Text('Minha biblioteca'),
                ),
              ],
            ),
          ),
          if (wide) ...[
            const SizedBox(width: 22),
            const BeastBrand(BeastArtwork.emblem, width: 156, height: 156),
          ],
        ],
      ),
    );
  }

  Widget sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
    );
  }

  Widget buildConsoles() {
    const consoles = [
      'Game Boy',
      'Game Boy Color',
      'Game Boy Advance',
      'Nintendo DS',
      'Nintendo 3DS',
    ];

    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: consoles.map((name) {
        final supported =
            name == 'Game Boy' ||
            name == 'Game Boy Color' ||
            name == 'Game Boy Advance';
        return InkWell(
          onTap: supported ? () => openConsole(name) : null,
          child: Container(
            width: 174,
            height: 140,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: beastPanel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.videogame_asset_outlined,
                  color: Colors.redAccent,
                  size: 32,
                ),
                const Spacer(),
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(
                  name == 'Game Boy' || name == 'Game Boy Color'
                      ? 'Disponível'
                      : name == 'Game Boy Advance'
                      ? 'Em teste'
                      : 'Planejado',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
