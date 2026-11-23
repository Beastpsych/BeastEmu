import 'dart:typed_data';

/// Selected at process launch. Single-player retains its original wire format.
const linkLaunchFlag = '--link-local-v1';
const linkWidth = 320;
const linkHeight = 144;

class JoypadPackets {
  JoypadPackets({required bool dual}) : _bytes = Uint8List(dual ? 4 : 2);
  final Uint8List _bytes;
  final masks = [0, 0];
  int _used = 0;

  void add(List<int> chunk) {
    for (final byte in chunk) {
      _bytes[_used++] = byte;
      if (_used != _bytes.length) continue;
      _used = 0;
      masks[0] = _bytes[0] | (_bytes[1] << 8);
      if (_bytes.length == 4) masks[1] = _bytes[2] | (_bytes[3] << 8);
    }
  }
}
