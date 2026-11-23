import 'dart:typed_data';

import 'package:beastemu/services/libretro_frame_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LibretroPixelFormat', () {
    test('reconhece os tres identificadores Libretro', () {
      expect(LibretroPixelFormat.fromLibretroValue(0), LibretroPixelFormat.rgb1555);
      expect(LibretroPixelFormat.fromLibretroValue(1), LibretroPixelFormat.xrgb8888);
      expect(LibretroPixelFormat.fromLibretroValue(2), LibretroPixelFormat.rgb565);
    });

    test('recusa identificador desconhecido', () {
      expect(() => LibretroPixelFormat.fromLibretroValue(999), throwsArgumentError);
    });
  });

  group('LibretroFrameConverter', () {
    test('XRGB8888 -> RGBA8888 com alpha opaco', () {
      // 0x00RRGGBB: pixels vermelhos e azuis em little-endian.
      final source = Uint8List.fromList([0, 0, 255, 77, 255, 0, 0, 66]);
      final rgba = LibretroFrameConverter.toRgba8888(
        pixels: source,
        width: 2,
        height: 1,
        pitch: 8,
        format: LibretroPixelFormat.xrgb8888,
      );
      expect(rgba, [255, 0, 0, 255, 0, 0, 255, 255]);
    });

    test('0RGB1555 -> RGBA8888', () {
      // Vermelho maximo = 0x7C00; verde maximo = 0x03E0.
      final rgba = LibretroFrameConverter.toRgba8888(
        pixels: Uint8List.fromList([0x00, 0x7c, 0xe0, 0x03]),
        width: 2,
        height: 1,
        pitch: 4,
        format: LibretroPixelFormat.rgb1555,
      );
      expect(rgba, [255, 0, 0, 255, 0, 255, 0, 255]);
    });

    test('RGB565 -> RGBA8888', () {
      // Verde maximo = 0x07E0; azul maximo = 0x001F.
      final rgba = LibretroFrameConverter.toRgba8888(
        pixels: Uint8List.fromList([0xe0, 0x07, 0x1f, 0x00]),
        width: 2,
        height: 1,
        pitch: 4,
        format: LibretroPixelFormat.rgb565,
      );
      expect(rgba, [0, 255, 0, 255, 0, 0, 255, 255]);
    });

    test('ignora bytes extras de pitch entre linhas', () {
      final rgba = LibretroFrameConverter.toRgba8888(
        pixels: Uint8List.fromList([
          0, 0, 255, 0, // primeira linha: vermelho
          9, 9, 9, 9, // padding nao e pixel
          0, 255, 0, 0, // segunda linha: verde
        ]),
        width: 1,
        height: 2,
        pitch: 8,
        format: LibretroPixelFormat.xrgb8888,
      );
      expect(rgba, [255, 0, 0, 255, 0, 255, 0, 255]);
    });

    test('recusa largura ou altura nao positiva', () {
      expect(
        () => LibretroFrameConverter.toRgba8888(
          pixels: Uint8List(4), width: 0, height: 1, pitch: 4,
          format: LibretroPixelFormat.xrgb8888,
        ),
        throwsArgumentError,
      );
      expect(
        () => LibretroFrameConverter.toRgba8888(
          pixels: Uint8List(4), width: 1, height: -1, pitch: 4,
          format: LibretroPixelFormat.xrgb8888,
        ),
        throwsArgumentError,
      );
    });

    test('recusa pitch insuficiente', () {
      expect(
        () => LibretroFrameConverter.toRgba8888(
          pixels: Uint8List(8), width: 2, height: 1, pitch: 4,
          format: LibretroPixelFormat.xrgb8888,
        ),
        throwsArgumentError,
      );
    });

    test('recusa buffer truncado', () {
      expect(
        () => LibretroFrameConverter.toRgba8888(
          pixels: Uint8List(7), width: 2, height: 1, pitch: 8,
          format: LibretroPixelFormat.xrgb8888,
        ),
        throwsArgumentError,
      );
    });

    test('permite ultima linha sem padding', () {
      final rgba = LibretroFrameConverter.toRgba8888(
        pixels: Uint8List.fromList([
          0, 0, 255, 0,
          99, 99, 99, 99,
          255, 0, 0, 0,
        ]),
        width: 1, height: 2, pitch: 8,
        format: LibretroPixelFormat.xrgb8888,
      );
      expect(rgba, [255, 0, 0, 255, 0, 0, 255, 255]);
    });
  });
}
