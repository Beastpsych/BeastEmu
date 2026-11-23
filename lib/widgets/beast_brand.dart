import 'package:flutter/widgets.dart';

enum BeastArtwork {
  horizontal('logo-horizontal'),
  compact('logo-compact'),
  emblem('emblem'),
  symbol('symbol');

  const BeastArtwork(this.filename);
  final String filename;
}

class BeastBrand extends StatelessWidget {
  const BeastBrand(
    this.artwork, {
    super.key,
    this.width,
    this.height,
    this.label,
  });

  final BeastArtwork artwork;
  final double? width;
  final double? height;
  final String? label;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/${artwork.filename}.png',
    width: width,
    height: height,
    fit: BoxFit.contain,
    semanticLabel: label,
    excludeFromSemantics: label == null,
  );
}
