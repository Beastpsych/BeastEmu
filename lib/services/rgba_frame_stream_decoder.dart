import 'dart:typed_data';

/// Reagrupa chunks TCP em quadros completos do Game Boy (160 x 144 RGBA).
/// TCP nao preserva as fronteiras entre chamadas Socket.add.
class RgbaFrameStreamDecoder {
  static const width = 160;
  static const height = 144;
  static const frameSize = width * height * 4;

  RgbaFrameStreamDecoder({int bytesPerFrame = frameSize})
    : _pending = Uint8List(bytesPerFrame),
      assert(bytesPerFrame > 0);
  final Uint8List _pending;
  int _length = 0;

  void add(Uint8List bytes, void Function(Uint8List) onFrame) {
    var cursor = 0;
    while (cursor < bytes.length) {
      final free = _pending.length - _length;
      final available = bytes.length - cursor;
      final count = free < available ? free : available;
      _pending.setRange(_length, _length + count, bytes, cursor);
      _length += count;
      cursor += count;
      if (_length == _pending.length) {
        onFrame(Uint8List.fromList(_pending));
        _length = 0;
      }
    }
  }
}
