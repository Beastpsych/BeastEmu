import 'dart:typed_data';

import 'rgba_frame_stream_decoder.dart';

/// GBA v1: the first four bytes are the little-endian AV width and height.
/// The rest of the session consists of tightly packed RGBA frames.
class GbaVideoDecoder {
  final _header = ByteData(4);
  int _used = 0;
  RgbaFrameStreamDecoder? _frames;
  int get width => _header.getUint16(0, Endian.little);
  int get height => _header.getUint16(2, Endian.little);

  void add(Uint8List chunk, void Function(Uint8List) onFrame) {
    var offset = 0;
    while (_used < 4 && offset < chunk.length) {
      _header.setUint8(_used++, chunk[offset++]);
    }
    if (_used != 4) return;
    if (width == 0 || height == 0 || width > 512 || height > 512) {
      throw const FormatException('Geometria GBA inválida.');
    }
    _frames ??= RgbaFrameStreamDecoder(bytesPerFrame: width * height * 4);
    _frames!.add(Uint8List.sublistView(chunk, offset), onFrame);
  }
}
