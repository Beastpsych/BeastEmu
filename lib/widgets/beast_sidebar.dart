import 'package:flutter/material.dart';
import 'package:beastemu/core/version.dart';
import 'package:beastemu/core/theme.dart';
import 'package:beastemu/widgets/beast_brand.dart';

/// Menu lateral do BeastEmu. Mantém o visual Beast Edition.
///
/// Recebe a página atual e avisa à tela principal quando outra página
/// é selecionada. A navegação continua controlada pelo BeastHome.
class BeastSidebar extends StatelessWidget {
  const BeastSidebar({
    super.key,
    required this.pages,
    required this.icons,
    required this.selectedPage,
    required this.onPageSelected,
  });

  final List<String> pages;
  final List<IconData> icons;
  final int selectedPage;
  final ValueChanged<int> onPageSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Material(
        color: beastPanel,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BeastBrand(
                        BeastArtwork.horizontal,
                        width: 194,
                        label: 'BeastEmu',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'BEAST EDITION',
                        style: TextStyle(
                          color: beastSilver,
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 45),
                      for (int i = 0; i < pages.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            selected: selectedPage == i,
                            selectedColor: Colors.white,
                            selectedTileColor: beastRed.withValues(alpha: 0.28),
                            leading: Icon(
                              icons[i],
                              color: selectedPage == i
                                  ? Colors.redAccent
                                  : Colors.grey,
                            ),
                            title: Text(pages[i]),
                            onTap: () => onPageSelected(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Text(
                'BeastEmu $beastEmuVersion',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
