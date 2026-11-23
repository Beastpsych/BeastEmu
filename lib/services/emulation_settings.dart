import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:beastemu/services/windows_profile.dart';

/// Preferências do frontend em arquivo próprio, independente do catálogo de ROMs.
class EmulationSettings extends ChangeNotifier {
  EmulationSettings({this.directory});

  final Directory? directory;
  Future<void>? _loading;
  Future<void>? _saving;
  bool _disposed = false;
  bool _dirty = false;

  int _volume = 100;
  bool _muted = false;
  int _scale = 0;
  bool _smooth = false;
  String? _storageMessage;

  int get volume => _volume;
  bool get muted => _muted;
  int get effectiveVolume => _muted ? 0 : _volume;

  /// Zero ajusta a imagem ao espaço disponível. 1 a 4 usam a resolução nativa.
  int get scale => _scale;
  bool get smooth => _smooth;
  String? get storageMessage => _storageMessage;

  Future<File> _settingsFile() async {
    final root = directory ?? await gameDataDirectory();
    return File('${root.path}/emulation-settings-v1.json');
  }

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Formato de preferências inválido.');
      }
      final volume = raw['volume'];
      final scale = raw['scale'];
      if (volume is int && volume >= 0 && volume <= 100) _volume = volume;
      if (scale is int && scale >= 0 && scale <= 4) _scale = scale;
      _muted = raw['muted'] == true;
      _smooth = raw['smooth'] == true;
    } catch (error) {
      debugPrint('Leitura das configurações de emulação: $error');
      _storageMessage =
          'Falha ao ler as preferências. Usando os valores padrão.';
    } finally {
      _notify();
    }
  }

  Future<void> setVolume(int value) => _change(volume: value.clamp(0, 100));
  Future<void> setMuted(bool value) => _change(muted: value);
  Future<void> setScale(int value) => _change(scale: value.clamp(0, 4));
  Future<void> setSmooth(bool value) => _change(smooth: value);

  Future<void> _change({
    int? volume,
    bool? muted,
    int? scale,
    bool? smooth,
  }) async {
    await load();
    if ((volume == null || volume == _volume) &&
        (muted == null || muted == _muted) &&
        (scale == null || scale == _scale) &&
        (smooth == null || smooth == _smooth) &&
        _storageMessage == null) {
      await _saving;
      return;
    }
    _volume = volume ?? _volume;
    _muted = muted ?? _muted;
    _scale = scale ?? _scale;
    _smooth = smooth ?? _smooth;
    _dirty = true;
    _notify();
    // Only the latest slider position matters while a disk write is pending.
    await (_saving ??= _save().whenComplete(() => _saving = null));
  }

  Future<void> _save() async {
    do {
      _dirty = false;
      final data = jsonEncode({
        'volume': volume,
        'muted': muted,
        'scale': scale,
        'smooth': smooth,
      });
      try {
        final file = await _settingsFile();
        await file.parent.create(recursive: true);
        final temp = File(
          '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
        );
        await temp.create(exclusive: true);
        try {
          await temp.writeAsString(data, flush: true);
          await temp.rename(file.path);
        } finally {
          if (await temp.exists()) await temp.delete();
        }
        if (_storageMessage != null) {
          _storageMessage = null;
          _notify();
        }
      } catch (error) {
        debugPrint('Gravação das configurações de emulação: $error');
        _storageMessage =
            'Falha ao gravar as preferências. Ajustes ativos nesta sessão.';
        _notify();
      }
    } while (_dirty);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
