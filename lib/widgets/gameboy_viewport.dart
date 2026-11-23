import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The emulated LCD has square pixels and a native resolution of 160 by 144.
class GameBoyViewport extends StatelessWidget {
  const GameBoyViewport({
    super.key,
    required this.scale,
    required this.child,
    this.nativeWidth = 160,
  });

  final int scale;
  final int nativeWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, bounds) {
          final fit = math.min(
            bounds.maxWidth / nativeWidth,
            bounds.maxHeight / 144,
          );
          final factor = scale == 0 ? fit : math.min(scale.toDouble(), fit);
          return Center(
            child: SizedBox(
              width: nativeWidth * factor,
              height: 144 * factor,
              child: child,
            ),
          );
        },
      ),
    );
  }
}
