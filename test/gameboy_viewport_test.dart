import 'package:beastemu/widgets/gameboy_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('LCD fits wide and short windows and respects fixed scale', (
    tester,
  ) async {
    const lcd = Key('lcd');
    Future<Size> measure(double w, double h, int scale) async {
      await tester.pumpWidget(
        Center(
          child: SizedBox(
            width: w,
            height: h,
            child: GameBoyViewport(
              scale: scale,
              child: const SizedBox(key: lcd),
            ),
          ),
        ),
      );
      return tester.getSize(find.byKey(lcd));
    }

    expect(await measure(600, 288, 0), const Size(320, 288));
    expect(await measure(600, 400, 1), const Size(160, 144));
    expect(await measure(240, 400, 4), const Size(240, 216));
  });
}
