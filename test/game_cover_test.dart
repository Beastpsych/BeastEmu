import 'dart:io';
import 'dart:ui' as ui;

import 'package:beastemu/services/game_cover_store.dart';
import 'package:beastemu/widgets/game_cover.dart';
import 'package:beastemu/widgets/beast_brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cache persiste por jogo e uma imagem inválida preserva a capa',
    () async {
      final dir = await Directory.systemTemp.createTemp('beast-cover-');
      addTearDown(() => dir.delete(recursive: true));
      final store = GameCoverStore(directory: dir);
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawColor(const Color(0xffbe1120), BlendMode.src);
      final picture = rec.endRecording();
      final image = await picture.toImage(12, 12);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      picture.dispose();
      final cached = await store.set('one', png);
      final saved = await cached.readAsBytes();
      expect(
        await (await GameCoverStore(directory: dir).find('one'))!.readAsBytes(),
        saved,
      );
      expect(await store.find('two'), isNull);
      await expectLater(store.set('one', png.sublist(0, 5)), throwsA(anything));
      expect(await cached.readAsBytes(), saved);
      await cached.delete();
      expect(await store.find('one'), isNull);
    },
  );
  testWidgets('capa ausente usa o visual Beast', (tester) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('beast-cover-ui-'),
    );
    addTearDown(() => dir!.delete(recursive: true));
    await tester.pumpWidget(
      MaterialApp(
        home: GameCover(
          id: 'absent',
          store: GameCoverStore(directory: dir),
        ),
      ),
    );
    expect(
      tester.widget<BeastBrand>(find.byType(BeastBrand)).artwork,
      BeastArtwork.symbol,
    );
  });
}
