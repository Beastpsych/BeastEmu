import 'dart:io';

import 'package:flutter/material.dart';
import 'package:beastemu/core/theme.dart';
import 'package:beastemu/widgets/beast_brand.dart';
import 'package:beastemu/services/game_cover_store.dart';

class GameCover extends StatefulWidget {
  const GameCover({super.key, required this.id, required this.store});
  final String id;
  final GameCoverStore store;
  @override
  State<GameCover> createState() => _GameCoverState();
}

class _GameCoverState extends State<GameCover> {
  late final Future<File?> _file = widget.store.find(widget.id);
  @override
  Widget build(BuildContext context) {
    const fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff3c1116), beastPanel],
        ),
      ),
      child: Center(
        child: BeastBrand(BeastArtwork.symbol, width: 64, height: 64),
      ),
    );
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FutureBuilder<File?>(
          future: _file,
          builder: (context, snapshot) {
            final file = snapshot.data;
            return file == null
                ? fallback
                : Image.file(
                    file,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => fallback,
                  );
          },
        ),
      ),
    );
  }
}
