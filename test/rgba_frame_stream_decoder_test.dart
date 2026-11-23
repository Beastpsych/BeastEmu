import 'dart:typed_data';

import 'package:beastemu/services/rgba_frame_stream_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('espera frame completo antes de emitir', () {
    final decoder = RgbaFrameStreamDecoder();
    final frames = <Uint8List>[];
    decoder.add(Uint8List(100), frames.add);
    expect(frames, isEmpty);
    decoder.add(Uint8List(RgbaFrameStreamDecoder.frameSize - 100), frames.add);
    expect(frames, hasLength(1));
    expect(frames.single.length, RgbaFrameStreamDecoder.frameSize);
  });

  test('reconstitui chunks e dois frames consecutivos', () {
    final decoder = RgbaFrameStreamDecoder();
    final frames = <Uint8List>[];
    final size = RgbaFrameStreamDecoder.frameSize;
    final data = Uint8List(size * 2);
    data.fillRange(0, size, 17);
    data.fillRange(size, size * 2, 231);
    decoder.add(Uint8List.sublistView(data, 0, size + 25), frames.add);
    expect(frames, hasLength(1));
    decoder.add(Uint8List.sublistView(data, size + 25), frames.add);
    expect(frames, hasLength(2));
    expect(frames[0][0], 17);
    expect(frames[0][size - 1], 17);
    expect(frames[1][0], 231);
    expect(frames[1][size - 1], 231);
  });
}
