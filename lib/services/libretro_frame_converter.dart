import 'dart:typed_data';

/// Formatos de pixels definidos pela API Libretro (libretro.h).
///
/// Os valores numericos sao usados pelo callback RETRO_ENVIRONMENT_SET_PIXEL_FORMAT.
enum LibretroPixelFormat {
  rgb1555(0, 2),
  xrgb8888(1, 4),
  rgb565(2, 2);

  const LibretroPixelFormat(this.libretroValue, this.bytesPerPixel);

  final int libretroValue;
  final int bytesPerPixel;

  static LibretroPixelFormat fromLibretroValue(int value) {
    for (final format in values) {
      if (format.libretroValue == value) return format;
    }
    throw ArgumentError.value(value, 'value', 'Formato Libretro nao suportado');
  }
}

/// Converte um frame de video da Libretro para bytes RGBA8888 do Flutter.
///
/// [pitch] e o numero de BYTES por linha, incluindo eventual preenchimento.
/// A entrada e interpretada em little-endian (Windows e Android convencionais).
///
/// O resultado tem exatamente width * height * 4 bytes, sem padding,
/// na ordem R, G, B, A, com canal alpha opaco (255).
///
/// Esta classe somente converte pixels. Nao executa o nucleo nem cria imagens
/// Flutter. Assim, pode ser testada sem abrir uma janela ou carregar ROMs.
class LibretroFrameConverter {
  const LibretroFrameConverter._();

  static Uint8List toRgba8888({
    required Uint8List pixels,
    required int width,
    required int height,
    required int pitch,
    required LibretroPixelFormat format,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Largura e altura precisam ser positivas.');
    }

    final rowBytes = width * format.bytesPerPixel;
    if (pitch < rowBytes) {
      throw ArgumentError.value(
        pitch,
        'pitch',
        'Menor que os bytes de pixels de uma linha ($rowBytes)',
      );
    }

    final minimumLength = (height - 1) * pitch + rowBytes;
    if (pixels.length < minimumLength) {
      throw ArgumentError.value(
        pixels.length,
        'pixels.length',
        'Buffer insuficiente: minimo $minimumLength bytes',
      );
    }

    final rgba = Uint8List(width * height * 4);
    final bytesPerPixel = format.bytesPerPixel;

    for (var y = 0; y < height; y++) {
      final sourceRow = y * pitch;
      final destRow = y * width * 4;

      for (var x = 0; x < width; x++) {
        final source = sourceRow + x * bytesPerPixel;
        final dest = destRow + x * 4;

        switch (format) {
          case LibretroPixelFormat.xrgb8888:
            // Valor nativo 0x00RRGGBB -> bytes B, G, R, X no little-endian.
            rgba[dest] = pixels[source + 2];
            rgba[dest + 1] = pixels[source + 1];
            rgba[dest + 2] = pixels[source];
          case LibretroPixelFormat.rgb1555:
            final value = pixels[source] | (pixels[source + 1] << 8);
            rgba[dest] = _expand5((value >> 10) & 0x1f);
            rgba[dest + 1] = _expand5((value >> 5) & 0x1f);
            rgba[dest + 2] = _expand5(value & 0x1f);
          case LibretroPixelFormat.rgb565:
            final value = pixels[source] | (pixels[source + 1] << 8);
            rgba[dest] = _expand5((value >> 11) & 0x1f);
            rgba[dest + 1] = _expand6((value >> 5) & 0x3f);
            rgba[dest + 2] = _expand5(value & 0x1f);
        }
        rgba[dest + 3] = 255;
      }
    }
    return rgba;
  }

  static int _expand5(int value) => (value << 3) | (value >> 2);
  static int _expand6(int value) => (value << 2) | (value >> 4);
}
