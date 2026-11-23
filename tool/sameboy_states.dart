import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';

import 'package:beastemu/services/sameboy_commands.dart';

typedef _Transfer = Bool Function(Pointer<Uint8>, Size);
typedef _Copy = bool Function(Pointer<Uint8>, int);

/// Called only between retro_run calls, in the isolate that owns the core.
class SameBoyStates {
  SameBoyStates(DynamicLibrary dll, this._rom, File core, Directory root)
    : _size = dll.lookupFunction<Size Function(), int Function()>(
        'retro_serialize_size',
      ),
      _capture = dll.lookupFunction<_Transfer, _Copy>('retro_serialize'),
      _restore = dll.lookupFunction<_Transfer, _Copy>('retro_unserialize'),
      _core = sha256.convert(core.readAsBytesSync()),
      _root = root;

  final int Function() _size;
  final _Copy _capture, _restore;
  final Digest _rom, _core;
  final Directory _root;
  final _seen = <int, String>{};

  // BST1 | ROM SHA256 | DLL SHA256 | UTC milliseconds LE | native state | SHA256.
  static const _offset = 76;
  File _file(int slot) => File('${_root.path}/$_rom/$slot.state');

  int get _length {
    final n = _size();
    if (n <= 0 || n > 8 * 1024 * 1024) {
      throw StateError('Tamanho de estado incompatível.');
    }
    return n;
  }

  Future<Uint8List> _read(File file) async {
    final handle = await file.open();
    try {
      final length = _offset + _length + 32;
      if (await handle.length() != length) {
        throw const FormatException('Tamanho incompatível.');
      }
      final bytes = await handle.read(length);
      final identity = [...'BST1'.codeUnits, ..._rom.bytes, ..._core.bytes];
      if (bytes.length != length ||
          !_matches(bytes, 0, identity) ||
          !_matches(
            bytes,
            length - 32,
            sha256.convert(Uint8List.sublistView(bytes, 0, length - 32)).bytes,
          )) {
        throw const FormatException(
          'Estado danificado ou de outra ROM/versão do núcleo.',
        );
      }
      return bytes;
    } finally {
      await handle.close();
    }
  }

  static bool _matches(Uint8List bytes, int offset, List<int> expected) {
    for (var i = 0; i < expected.length; i++) {
      if (bytes[offset + i] != expected[i]) return false;
    }
    return true;
  }

  Future<List<String?>> list() async {
    final entries = <String?>[];
    _seen.clear();
    for (var slot = 1; slot <= 5; slot++) {
      final file = _file(slot);
      if (!await file.exists()) {
        entries.add(null);
        continue;
      }
      try {
        final data = await _read(file);
        final stamp = ByteData.sublistView(data).getInt64(68, Endian.little);
        entries.add(
          DateTime.fromMillisecondsSinceEpoch(
            stamp,
            isUtc: true,
          ).toIso8601String(),
        );
        _seen[slot] = _checksum(data);
      } catch (_) {
        entries.add('Incompatível ou ilegível');
      }
    }
    return entries;
  }

  String _checksum(Uint8List bytes) =>
      Digest(Uint8List.sublistView(bytes, bytes.length - 32)).toString();

  Future<void> execute(
    int command,
    Future<void> Function() protectCartridge,
  ) async {
    if (command <= listStateSlots || !isStateCommand(command)) {
      throw ArgumentError.value(command);
    }
    final slot = (command - listStateSlots - 1) % 5 + 1;
    final quick = command == quickSave || command == quickLoad;
    final file = quick ? File('${_root.path}/$_rom/quick.state') : _file(slot);
    if (command == quickLoad || (!quick && command > loadStateBase)) {
      if (quick && !await file.exists()) throw const EmptyQuickSlot();
      final data = await _read(file);
      if (!quick && _seen[slot] != _checksum(data)) {
        throw StateError('O slot mudou. Reabra o menu.');
      }
      final n = data.length - _offset - 32;
      final ptr = calloc<Uint8>(n);
      try {
        ptr.asTypedList(n).setRange(0, n, data, _offset);
        await protectCartridge();
        if (!_restore(ptr, n)) throw StateError('O núcleo recusou o estado.');
      } finally {
        calloc.free(ptr);
      }
      return;
    }

    await file.parent.create(recursive: true);
    final lock = await File('${file.path}.lock').open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      if (await file.exists()) {
        final previous = await _read(file);
        if (!quick &&
            (command <= replaceStateBase ||
                _seen[slot] != _checksum(previous))) {
          throw StateError('O slot está ocupado ou mudou. Reabra o menu.');
        }
      } else if (!quick && command > replaceStateBase) {
        throw StateError('O slot foi removido. Reabra o menu.');
      }
      final n = _length;
      final data = Uint8List(_offset + n + 32)
        ..setAll(0, 'BST1'.codeUnits)
        ..setAll(4, _rom.bytes)
        ..setAll(36, _core.bytes);
      ByteData.sublistView(data)
          .setInt64(68, DateTime.now().millisecondsSinceEpoch, Endian.little);
      final ptr = calloc<Uint8>(n);
      try {
        if (!_capture(ptr, n)) throw StateError('O núcleo recusou a captura.');
        data.setRange(_offset, _offset + n, ptr.asTypedList(n));
      } finally {
        calloc.free(ptr);
      }
      data.setAll(
        _offset + n,
        sha256.convert(Uint8List.sublistView(data, 0, _offset + n)).bytes,
      );
      final tmp = File('${file.path}.$pid.tmp');
      await tmp.create(exclusive: true);
      try {
        await tmp.writeAsBytes(data, flush: true);
        await tmp.rename(file.path);
      } finally {
        if (await tmp.exists()) await tmp.delete();
      }
    } finally {
      await lock.close();
    }
  }
}
