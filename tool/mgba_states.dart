import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';

import 'package:beastemu/services/sameboy_commands.dart';

typedef _Transfer = Bool Function(Pointer<Uint8>, Size);
typedef _Copy = bool Function(Pointer<Uint8>, int);

/// mGBA state files deliberately have their own format. The native payload
/// includes the cart's save data, but [protectCartridge] keeps the separately
/// persisted cartridge timeline ahead of a loaded, older state.
class MgbaStates {
  MgbaStates(
    DynamicLibrary dll,
    this._rom,
    File core,
    String coreVersion,
    Directory root,
  ) : _size = dll.lookupFunction<Size Function(), int Function()>(
        'retro_serialize_size',
      ),
      _capture = dll.lookupFunction<_Transfer, _Copy>('retro_serialize'),
      _restore = dll.lookupFunction<_Transfer, _Copy>('retro_unserialize'),
      _ramSize = dll.lookupFunction<Size Function(Uint32), int Function(int)>(
        'retro_get_memory_size',
      ),
      _ramData = dll
          .lookupFunction<
            Pointer<Uint8> Function(Uint32),
            Pointer<Uint8> Function(int)
          >('retro_get_memory_data'),
      _core = sha256.convert(core.readAsBytesSync()),
      _revision = sha256.convert(utf8.encode('mGBA\u0000$coreVersion')),
      _root = root;

  final int Function() _size;
  final _Copy _capture, _restore;
  final int Function(int) _ramSize;
  final Pointer<Uint8> Function(int) _ramData;
  final Digest _rom, _core, _revision;
  final Directory _root;
  final _seen = <int, String>{};

  // BGA1 | format | ROM SHA256 | DLL SHA256 | mGBA version SHA256 | slot |
  // UTC milliseconds LE | payload size LE | native state | SHA256.
  static const _offset = 118;
  static const _format = 1;
  File _file(int slot) => File('${_root.path}/$_rom/$slot.state');
  File get _quick => File('${_root.path}/$_rom/quick.state');

  int get _length {
    final n = _size();
    if (n <= 0 || n > 32 * 1024 * 1024) {
      throw StateError('Tamanho de estado mGBA incompatível.');
    }
    return n;
  }

  Future<Uint8List> _read(File file, {int? expectedSlot}) async {
    final handle = await file.open();
    try {
      final length = await handle.length();
      if (length < _offset + 32 || length > 32 * 1024 * 1024 + _offset + 32) {
        throw const FormatException('Tamanho de estado incompatível.');
      }
      final data = await handle.read(length);
      final view = ByteData.sublistView(data);
      final payload = view.getUint32(110, Endian.little);
      final ram = view.getUint32(114, Endian.little);
      final identity = [
        ...'BGA1'.codeUnits,
        _format,
        ..._rom.bytes,
        ..._core.bytes,
        ..._revision.bytes,
      ];
      if (data.length != length ||
          payload <= 0 ||
          payload > 32 * 1024 * 1024 ||
          !{0, 512, 8192, 32768, 65536, 131072}.contains(ram) ||
          length != _offset + payload + ram + 32 ||
          !_matches(data, 0, identity) ||
          (expectedSlot != null && data[101] != expectedSlot) ||
          !_matches(
            data,
            length - 32,
            sha256.convert(Uint8List.sublistView(data, 0, length - 32)).bytes,
          )) {
        throw const FormatException(
          'Estado danificado ou de outra ROM/versão do núcleo.',
        );
      }
      return data;
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

  String _checksum(Uint8List data) =>
      Digest(Uint8List.sublistView(data, data.length - 32)).toString();

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
        final data = await _read(file, expectedSlot: slot);
        final stamp = ByteData.sublistView(data).getInt64(102, Endian.little);
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

  Future<void> execute(
    int command,
    Future<void> Function() protectCartridge,
  ) async {
    if (command <= listStateSlots || !isStateCommand(command)) {
      throw ArgumentError.value(command);
    }
    final quick = command == quickSave || command == quickLoad;
    final slot = quick ? 0 : (command - listStateSlots - 1) % 5 + 1;
    final file = quick ? _quick : _file(slot);
    final load = command == quickLoad || (!quick && command > loadStateBase);
    if (load) {
      if (quick && !await file.exists()) throw const EmptyQuickSlot();
      final data = await _read(file, expectedSlot: slot);
      if (!quick && _seen[slot] != _checksum(data)) {
        throw StateError('O slot mudou. Reabra o menu.');
      }
      final n = ByteData.sublistView(data).getUint32(110, Endian.little);
      final ram = ByteData.sublistView(data).getUint32(114, Endian.little);
      final ptr = calloc<Uint8>(n);
      try {
        ptr.asTypedList(n).setRange(0, n, data, _offset);
        await protectCartridge();
        if (!_restore(ptr, n)) throw StateError('O núcleo recusou o estado.');
        if (_ramSize(0) != ram || (ram > 0 && _ramData(0) == nullptr)) {
          throw StateError('Memória restaurada incompatível. Reabra a sessão.');
        }
        if (ram > 0) {
          _ramData(0).asTypedList(ram).setRange(0, ram, data, _offset + n);
        }
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
        final previous = await _read(file, expectedSlot: slot);
        if (!quick &&
            (command <= replaceStateBase ||
                _seen[slot] != _checksum(previous))) {
          throw StateError('O slot está ocupado ou mudou. Reabra o menu.');
        }
      } else if (!quick && command > replaceStateBase) {
        throw StateError('O slot foi removido. Reabra o menu.');
      }
      final n = _length;
      final ram = _ramSize(0);
      if (!{0, 512, 8192, 32768, 65536, 131072}.contains(ram)) {
        throw StateError('Memória de cartucho incompatível.');
      }
      final data = Uint8List(_offset + n + ram + 32)
        ..setAll(0, 'BGA1'.codeUnits)
        ..[4] = _format
        ..setAll(5, _rom.bytes)
        ..setAll(37, _core.bytes)
        ..setAll(69, _revision.bytes)
        ..[101] = slot;
      ByteData.sublistView(data)
        ..setInt64(102, DateTime.now().millisecondsSinceEpoch, Endian.little)
        ..setUint32(110, n, Endian.little)
        ..setUint32(114, ram, Endian.little);
      final ptr = calloc<Uint8>(n);
      try {
        if (!_capture(ptr, n)) throw StateError('O núcleo recusou a captura.');
        data.setRange(_offset, _offset + n, ptr.asTypedList(n));
        if (ram > 0) {
          data.setRange(
            _offset + n,
            _offset + n + ram,
            _ramData(0).asTypedList(ram),
          );
        }
      } finally {
        calloc.free(ptr);
      }
      data.setAll(
        _offset + n + ram,
        sha256.convert(Uint8List.sublistView(data, 0, _offset + n + ram)).bytes,
      );
      final tmp = File('${file.path}.$pid.tmp');
      await tmp.create(exclusive: true);
      try {
        await tmp.writeAsBytes(data, flush: true);
        final verified = await _read(tmp, expectedSlot: slot);
        if (_checksum(verified) != _checksum(data)) {
          throw const FormatException('Falha ao verificar a gravação.');
        }
        await tmp.rename(file.path);
      } finally {
        if (await tmp.exists()) await tmp.delete();
      }
    } finally {
      await lock.close();
    }
  }
}
