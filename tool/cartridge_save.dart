import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Live views are scoped to a loaded cartridge in the SameBoy helper.
/// Disk I/O only uses owned copies. One lock covers restore through final flush.
class CartridgeSave {
  CartridgeSave._(this.file, this._lock, this._ram, this._rtc, this._header);

  final File file;
  final RandomAccessFile _lock;
  final Uint8List _ram;
  final Uint8List _rtc;
  final Uint8List _header;
  late Uint8List _lastPayload;
  Uint8List? _lastFile;
  Future<void>? _pending;
  bool _suspended = false;
  bool _reportedWriteError = false;

  static Future<CartridgeSave?> attach(
    DynamicLibrary core,
    Uint8List rom, {
    int? linkPort,
  }) async {
    if (linkPort != null && linkPort != 0 && linkPort != 1) {
      throw ArgumentError.value(linkPort);
    }
    final size = core.lookupFunction<Size Function(Uint32), int Function(int)>(
      'retro_get_memory_size',
    );
    final data = core
        .lookupFunction<
          Pointer<Uint8> Function(Uint32),
          Pointer<Uint8> Function(int)
        >('retro_get_memory_data');
    Uint8List region(int id) {
      final length = size(id);
      if (length == 0) return Uint8List(0);
      final pointer = data(id);
      if (pointer == nullptr || length > 1024 * 1024 || length < 0) {
        throw StateError('Memoria de cartucho invalida: id=$id size=$length');
      }
      return pointer.asTypedList(length);
    }

    final ram = region(switch (linkPort) {
      0 => 0x100,
      1 => 0x300,
      _ => 0,
    });
    final rtc = region(switch (linkPort) {
      0 => 0x201,
      1 => 0x401,
      _ => 1,
    });
    if (ram.isEmpty && rtc.isEmpty) return null;
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty) {
      throw StateError('LOCALAPPDATA indisponivel para os saves.');
    }
    final suffix = linkPort == null ? '' : '/link/p${linkPort + 1}';
    return open(Directory('$local/BeastEmu/saves$suffix'), rom, ram, rtc);
  }

  static Future<CartridgeSave> open(
    Directory directory,
    Uint8List rom,
    Uint8List ram,
    Uint8List rtc,
  ) async {
    final id = sha256.convert(rom);
    final file = File('${directory.path}/$id.cart');
    await directory.create(recursive: true);
    final lock = await File('${file.path}.lock').open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      // v1: magic/version, ROM SHA-256, two little-endian lengths, payload,
      // then SHA-256 of everything preceding the checksum.
      final lengths = ByteData(8)
        ..setUint32(0, ram.length, Endian.little)
        ..setUint32(4, rtc.length, Endian.little);
      final header = Uint8List.fromList([
        ...'BCAR'.codeUnits,
        1,
        ...id.bytes,
        ...lengths.buffer.asUint8List(),
      ]);
      final save = CartridgeSave._(file, lock, ram, rtc, header);
      final disk = await save._readExisting();
      if (disk != null) {
        final end = disk.length - 32;
        if (!_equal(header, Uint8List.sublistView(disk, 0, header.length)) ||
            !_equal(
              sha256.convert(Uint8List.sublistView(disk, 0, end)).bytes,
              Uint8List.sublistView(disk, end),
            )) {
          throw FormatException('Identidade, layout ou checksum invalido.');
        }
        ram.setRange(0, ram.length, disk, header.length);
        rtc.setRange(0, rtc.length, disk, header.length + ram.length);
      }
      save._lastFile = disk;
      save._lastPayload = save._snapshot();
      return save;
    } catch (error) {
      await lock.close();
      await _logError(file, error);
      throw FileSystemException('Falha ao abrir save: $error', file.path);
    }
  }

  static Future<void> _logError(File file, Object error) async {
    final message = 'Save ${file.path}: $error';
    stderr.writeln(message);
    try {
      await File('${file.path}.errors.log').writeAsString(
        '${DateTime.now().toIso8601String()} $message\n',
        mode: FileMode.append,
      );
    } on FileSystemException {
      // stderr remains available if the save directory itself is read-only.
    }
  }

  Future<Uint8List?> _readExisting() async {
    RandomAccessFile handle;
    try {
      handle = await file.open();
    } on PathNotFoundException catch (error) {
      if (error.osError?.errorCode == 2) return null;
      rethrow;
    }
    try {
      final length = _header.length + _ram.length + _rtc.length + 32;
      if (await handle.length() != length) {
        throw FormatException('Tamanho de save incompativel: ${file.path}');
      }
      final bytes = await handle.read(length);
      if (bytes.length != length) {
        throw const FormatException('Leitura parcial.');
      }
      return bytes;
    } finally {
      await handle.close();
    }
  }

  Uint8List _snapshot() => Uint8List(_ram.length + _rtc.length)
    ..setAll(0, _ram)
    ..setAll(_ram.length, _rtc);

  static bool _equal(List<int>? a, List<int>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // Called between retro_run calls. A slow disk never queues stale snapshots.
  Future<void> checkpoint() =>
      _pending ??= _writeChanges().whenComplete(() => _pending = null);

  Future<void> _writeChanges() async {
    if (_suspended) return;
    if (_equal(_ram, Uint8List.sublistView(_lastPayload, 0, _ram.length)) &&
        _equal(_rtc, Uint8List.sublistView(_lastPayload, _ram.length))) {
      return;
    }
    final payload = _snapshot();
    try {
      final body = Uint8List(_header.length + payload.length)
        ..setAll(0, _header)
        ..setAll(_header.length, payload);
      final bytes = Uint8List(body.length + 32)
        ..setAll(0, body)
        ..setAll(body.length, sha256.convert(body).bytes);
      final temp = File(
        '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      await temp.create(exclusive: true);
      try {
        await temp.writeAsBytes(bytes, flush: true);
        if (!_equal(await _readExisting(), _lastFile)) {
          throw StateError('Arquivo alterado fora da sessao.');
        }
        await temp.rename(file.path);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
      _lastPayload = payload;
      _lastFile = bytes;
      _reportedWriteError = false;
    } catch (error) {
      if (!_reportedWriteError) {
        await _logError(file, error);
      }
      _reportedWriteError = true;
    }
  }

  /// A state may replace both SRAM and RTC. Flush the original timeline first
  /// and keep the lock until shutdown; restored bytes must never reach .cart.
  Future<void> protectBeforeStateLoad() async {
    if (_suspended) return;
    await _pending;
    await checkpoint();
    if (_reportedWriteError) throw StateError('Falha ao preservar o cartucho.');
    _suspended = true;
  }

  Future<void> close({bool reportFailure = false}) async {
    try {
      await _pending;
      await checkpoint(); // Includes changes since the last in-flight snapshot.
      if (reportFailure && _reportedWriteError) {
        throw FileSystemException('Falha ao salvar cartucho', file.path);
      }
    } finally {
      await _lock.close();
    }
  }
}
