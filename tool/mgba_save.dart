import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Each manifest names immutable raw images. Publishing the manifest is the
/// only commit point. A crash may leave an unreferenced image or temporary file.
class MgbaSave {
  MgbaSave._(this.dir, this.romId, this.region, this.report, this.lock);
  final Directory dir;
  final String romId;
  final Uint8List Function() region;
  final void Function(String) report;
  final RandomAccessFile lock;
  static const sizes = {512, 8192, 32768, 65536, 131072};
  static final _digest = RegExp(r'^[0-9a-f]{64}$');
  File get index => File('${dir.path}/cart.json');
  File image(String hash) => File('${dir.path}/$hash.sav');
  String? current, previous;
  Uint8List? _manifest, _saved;
  late Uint8List _initial;
  Future<void>? _pending;
  Object? _failure;
  bool _protectedByState = false;

  static Future<MgbaSave> attach(
    DynamicLibrary lib,
    String id,
    void Function(String) report,
  ) {
    final size = lib.lookupFunction<Size Function(Uint32), int Function(int)>(
      'retro_get_memory_size',
    );
    final data = lib
        .lookupFunction<
          Pointer<Uint8> Function(Uint32),
          Pointer<Uint8> Function(int)
        >('retro_get_memory_data');
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty) {
      throw StateError('Pasta de dados indisponível.');
    }
    return open(Directory('$local/BeastEmu/saves/mgba'), id, () {
      final n = size(0);
      if (n == 0) return Uint8List(0);
      final ptr = data(0);
      if (!sizes.contains(n) || ptr == nullptr) {
        throw StateError('Memória GBA incompatível ($n bytes).');
      }
      return ptr.asTypedList(n);
    }, report);
  }

  static Future<MgbaSave> open(
    Directory root,
    String id,
    Uint8List Function() region,
    void Function(String) report,
  ) async {
    if (!_digest.hasMatch(id)) throw ArgumentError('SHA-256 de ROM inválido.');
    final dir = await Directory('${root.path}/$id').create(recursive: true);
    final lock = await File('${dir.path}/cart.lock')
        .open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      final store = MgbaSave._(dir, id, region, report, lock);
      await store._restore();
      return store;
    } catch (_) {
      await lock.close();
      rethrow;
    }
  }

  static Future<Uint8List?> _read(File file, int max) async {
    RandomAccessFile handle;
    try {
      handle = await file.open();
    } on PathNotFoundException catch (e) {
      if (e.osError?.errorCode == 2) return null;
      rethrow;
    }
    try {
      final n = await handle.length();
      if (n <= 0 || n > max) {
        throw FormatException('Tamanho inválido em ${file.path}.');
      }
      final bytes = await handle.read(n);
      if (bytes.length != n) {
        throw const FormatException('Leitura incompleta do save.');
      }
      return bytes;
    } finally {
      await handle.close();
    }
  }

  Future<Uint8List> _readImage(String hash) async {
    if (!_digest.hasMatch(hash)) {
      throw const FormatException('Identificador de save inválido.');
    }
    final bytes = await _read(image(hash), 131072);
    if (bytes == null ||
        !sizes.contains(bytes.length) ||
        sha256.convert(bytes).toString() != hash) {
      throw const FormatException(
        'Save ausente, incompatível ou com SHA-256 incorreto.',
      );
    }
    return bytes;
  }

  Future<void> _restore() async {
    _manifest = await _read(index, 1024);
    if (_manifest case final bytes?) {
      final meta = jsonDecode(utf8.decode(bytes)) as Map;
      if (meta['version'] != 1 ||
          meta['rom'] != romId ||
          meta['checksum'] != _checksum(meta['current'], meta['previous'])) {
        throw const FormatException(
          'Índice de save incompatível ou danificado.',
        );
      }
      current = meta['current'] as String?;
      previous = meta['previous'] as String?;
      if (previous != null) await _readImage(previous!);
      if (current != null) _saved = await _readImage(current!);
    } else if (await dir.list().any(
      (entry) => entry.path.toLowerCase().endsWith('.sav'),
    )) {
      throw const FormatException(
        'Índice ausente em pasta com saves. Arquivos preservados.',
      );
    }
    final ram = region();
    final saved = _saved;
    if (saved != null) {
      if (ram.length != saved.length && ram.length != 131072) {
        throw const FormatException('Memória inicial incompatível com o save.');
      }
      ram.setAll(0, saved);
    }
    _initial = Uint8List.fromList(ram);
    report(
      saved == null
          ? (ram.isEmpty
                ? 'Cartucho sem memória de save disponível'
                : 'Aguardando dados de cartucho')
          : 'Save restaurado (${saved.length} bytes)',
    );
  }

  String _checksum(Object? active, Object? backup) => sha256
      .convert(utf8.encode(jsonEncode([1, romId, active, backup])))
      .toString();

  Uint8List _metadata(String? active, String? backup) => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'version': 1,
        'rom': romId,
        'current': active,
        'previous': backup,
        'checksum': _checksum(active, backup),
      }),
    ),
  );

  static bool _equals(List<int>? a, List<int>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _publish(File file, Uint8List bytes) async {
    final tmp = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tmp.create(exclusive: true);
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      if (!_equals(await _read(tmp, bytes.length), bytes)) {
        throw const FormatException('Falha ao verificar gravação.');
      }
      await tmp.rename(file.path);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }

  Future<void> _verifyIndex() async {
    if (!_equals(await _read(index, 1024), _manifest)) {
      throw StateError('Índice alterado fora da sessão.');
    }
  }

  static bool _growth(int small, int large) =>
      (small == 512 && large == 8192) || (small == 65536 && large == 131072);

  Future<void> _checkpoint({required bool finalCheck}) async {
    final ram = region();
    final saved = _saved;
    // Compare with the exact pre-run image, including the erased tail in
    // autodetect. Never infer Flash1M merely from the initial capacity.
    if (ram.isEmpty) {
      if (saved != null) throw StateError('Memória do cartucho indisponível.');
      return;
    }
    if (_equals(ram, saved)) return;
    final unchanged =
        ram.length <= _initial.length &&
        _equals(ram, Uint8List.sublistView(_initial, 0, ram.length));
    if (unchanged &&
        (saved == null ||
            ram.length == 131072 ||
            _growth(ram.length, saved.length) ||
            _growth(saved.length, ram.length))) {
      return;
    }
    if (!sizes.contains(ram.length)) {
      throw StateError('Tamanho de cartucho desconhecido.');
    }
    if (saved != null &&
        ram.length != saved.length &&
        !_growth(saved.length, ram.length)) {
      if (_growth(ram.length, saved.length) && !finalCheck) return;
      throw StateError('Tamanho detectado incompatível com o save existente.');
    }
    if (ram.every((v) => v == 255) || ram.every((v) => v == 0)) {
      if (saved != null && finalCheck) {
        throw StateError('Memória vazia. Save anterior preservado.');
      }
      return;
    }
    final bytes = Uint8List.fromList(
      ram,
    ); // Own all bytes before the first await.
    final hash = sha256.convert(bytes).toString();
    await _verifyIndex();
    if (current != null) await _readImage(current!);
    if (previous != null) await _readImage(previous!);
    if (_manifest == null) {
      // Make even the first interrupted transaction recoverable.
      final empty = _metadata(null, null);
      await _publish(index, empty);
      _manifest = empty;
    }
    final dest = image(hash);
    if (await dest.exists()) {
      await _readImage(hash);
    } else {
      await _publish(dest, bytes);
    }
    final next = _metadata(hash, current);
    await _verifyIndex();
    await _publish(index, next);
    final obsolete = previous;
    previous = current;
    current = hash;
    _manifest = next;
    _saved = bytes;
    // Baseline for later size transitions is the latest committed payload.
    _initial = Uint8List(131072)
      ..fillRange(0, 131072, 255)
      ..setAll(0, bytes);
    if (obsolete != null && obsolete != current && obsolete != previous) {
      await _readImage(obsolete);
      await image(obsolete).delete();
    }
    report('Cartucho salvo (${bytes.length} bytes)');
  }

  void tick() {
    if (_protectedByState || _failure != null || _pending != null) return;
    _pending = _checkpoint(finalCheck: false)
        .catchError((Object error) {
          _failure = error;
          report('Falha no save: $error');
        })
        .whenComplete(() => _pending = null);
  }

  Future<void> close({required bool flush}) async {
    try {
      await _pending;
      if (_failure case final error?) throw StateError('Falha no save: $error');
      if (flush && !_protectedByState) await _checkpoint(finalCheck: true);
    } finally {
      await lock.close();
    }
  }

  /// Stores the current normal-cartridge timeline before a state load and
  /// stops periodic/final writes from publishing the older restored bytes.
  /// A state session remains usable, while the on-disk cartridge stays at
  /// the latest confirmed normal save until a new session begins.
  Future<void> protectBeforeStateLoad() async {
    if (_protectedByState) return;
    await _pending;
    if (_failure case final error?) throw StateError('Falha no save: $error');
    await _checkpoint(finalCheck: true);
    _protectedByState = true;
    report('Cartucho protegido após carregar estado');
  }
}
