import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:beastemu/services/windows_profile.dart';

enum GameBoyButton {
  up('Cima'),
  down('Baixo'),
  left('Esquerda'),
  right('Direita'),
  a('A'),
  b('B'),
  start('Start'),
  select('Select');

  const GameBoyButton(this.label);
  final String label;
}

enum EmulatorShortcut {
  quickSave('Salvar estado rápido', LogicalKeyboardKey.f5),
  quickLoad('Carregar estado rápido', LogicalKeyboardKey.f9),
  mute('Alternar mudo', LogicalKeyboardKey.keyM),
  cycleSpeed('Alternar velocidade', LogicalKeyboardKey.f8),
  holdSpeed('Acelerar enquanto pressionada', LogicalKeyboardKey.tab),
  fullscreen('Tela cheia', LogicalKeyboardKey.f11);

  const EmulatorShortcut(this.label, this.defaultKey);
  final String label;
  final LogicalKeyboardKey defaultKey;
}

class KeyboardBindings extends ChangeNotifier {
  KeyboardBindings({this.directory});

  static const _defaults = <GameBoyButton, List<LogicalKeyboardKey>>{
    GameBoyButton.up: [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW],
    GameBoyButton.down: [LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyS],
    GameBoyButton.left: [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA],
    GameBoyButton.right: [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.keyD,
    ],
    GameBoyButton.a: [LogicalKeyboardKey.keyX],
    GameBoyButton.b: [LogicalKeyboardKey.keyZ],
    GameBoyButton.start: [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
    ],
    GameBoyButton.select: [
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
    ],
  };

  static final _reserved = {
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.altGraph,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.unidentified,
  };

  static bool get shortcutModifierPressed {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed;
  }

  final Directory? directory;
  final _overrides = <GameBoyButton, LogicalKeyboardKey>{};
  final _shortcuts = <EmulatorShortcut, LogicalKeyboardKey>{};

  LogicalKeyboardKey? shortcutKey(EmulatorShortcut action) {
    final custom = _shortcuts[action];
    final key = custom ?? action.defaultKey;
    // An existing game binding or an explicitly assigned shortcut takes priority.
    if (buttonFor(key) != null ||
        (custom == null && _shortcuts.containsValue(key))) {
      return null;
    }
    return key;
  }

  EmulatorShortcut? actionFor(LogicalKeyboardKey key) {
    for (final action in EmulatorShortcut.values) {
      if (shortcutKey(action) == key) return action;
    }
    return null;
  }

  bool _disposed = false;
  Future<void>? _loading;
  Future<void> _writing = Future.value();
  String? _storageMessage;
  String? get storageMessage => _storageMessage;

  List<LogicalKeyboardKey> keysFor(GameBoyButton button) {
    final custom = _overrides[button];
    return custom == null ? _defaults[button]! : [custom];
  }

  GameBoyButton? buttonFor(LogicalKeyboardKey key) {
    for (final button in GameBoyButton.values) {
      if (keysFor(button).contains(key)) return button;
    }
    return null;
  }

  String? validate(
    GameBoyButton? button,
    LogicalKeyboardKey key, {
    EmulatorShortcut? shortcut,
  }) {
    if (_reserved.contains(key)) return 'Tecla reservada. Escolha outra tecla.';
    final action = actionFor(key);
    if (action != null && action != shortcut) {
      return 'Essa tecla está em uso: ${action.label}. Escolha outra tecla.';
    }
    final owner = buttonFor(key);
    if (owner != null && owner != button) {
      return 'Essa tecla já controla ${owner.label}. Escolha outra tecla.';
    }
    return null;
  }

  Future<File> _file() async {
    final dir = directory ?? await gameDataDirectory();
    return File('${dir.path}/keyboard-bindings-v1.json');
  }

  Future<void> load() => _loading ??= _read();
  Future<void> _read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      final keys = <LogicalKeyboardKey>{};
      for (final button in GameBoyButton.values) {
        if (decoded.containsKey(button.name)) {
          final id = decoded[button.name];
          if (id is! int || id <= 0 || id > 0x1fffffffffffff) {
            throw const FormatException();
          }
          _overrides[button] = LogicalKeyboardKey(id);
        }
        for (final key in keysFor(button)) {
          if (_reserved.contains(key) || !keys.add(key)) {
            throw const FormatException();
          }
        }
      }
      final saved = decoded['shortcuts'];
      for (final action in EmulatorShortcut.values) {
        final id = saved is Map
            ? saved[action.name]
            : action == EmulatorShortcut.holdSpeed
            ? decoded['fastForward']
            : null;
        if (id is! int || id <= 0 || id > 0x1fffffffffffff) continue;
        final key = LogicalKeyboardKey(id);
        if (!_reserved.contains(key) &&
            buttonFor(key) == null &&
            !_shortcuts.containsValue(key)) {
          _shortcuts[action] = key;
        }
      }
    } catch (error) {
      _overrides.clear();
      _storageMessage = 'Falha ao ler o mapeamento. Usando o teclado padrão.';
      debugPrint('Mapeamento do teclado: $error');
    } finally {
      _notify();
    }
  }

  Future<void> bind(GameBoyButton button, LogicalKeyboardKey key) async {
    await load();
    final error = validate(button, key);
    if (error != null) throw ArgumentError(error);
    _overrides[button] = key;
    await _persist();
  }

  Future<void> bindShortcut(
    EmulatorShortcut action,
    LogicalKeyboardKey key,
  ) async {
    await load();
    final error = validate(null, key, shortcut: action);
    if (error != null) throw ArgumentError(error);
    _shortcuts[action] = key;
    await _persist();
  }

  Future<void> restoreShortcuts() async {
    await load();
    _shortcuts.clear();
    await _persist();
  }

  Future<void> restoreDefaults() async {
    await load();
    _overrides.clear();
    await _persist();
  }

  Future<void> _persist() {
    final data = jsonEncode({
      'shortcuts': {
        for (final entry in _shortcuts.entries)
          entry.key.name: entry.value.keyId,
      },
      for (final entry in _overrides.entries) entry.key.name: entry.value.keyId,
    });
    _notify();
    // Key reassignment is infrequent. Keep writes in user action order.
    return _writing = _writing.then((_) => _save(data));
  }

  Future<void> _save(String data) async {
    String? message;
    try {
      final file = await _file();
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
    } catch (error) {
      message = 'Falha ao salvar o mapeamento. Teclas ativas nesta sessão.';
      debugPrint('Gravação do teclado: $error');
    }
    if (message != _storageMessage) {
      _storageMessage = message;
      _notify();
    }
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
