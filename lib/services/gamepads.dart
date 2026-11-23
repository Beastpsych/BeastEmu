import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'keyboard_bindings.dart';
import 'xinput.dart';

enum PadPlayer { one, two }

const _stickAlias = {
  PadControl.up: PadControl.stickUp,
  PadControl.down: PadControl.stickDown,
  PadControl.left: PadControl.stickLeft,
  PadControl.right: PadControl.stickRight,
};

class Gamepads extends ChangeNotifier {
  Gamepads({this.watch = watchXInput, this.preferences});
  final Stream<List<int?>> Function() watch;
  final SharedPreferencesAsync? preferences;
  // Use the same Windows preferences backend as the library. The previous
  // API added this prefix and cached a separate copy of the entire catalog.
  static const _key = 'flutter.xinput-bindings-v1';
  static const _defaults = {
    GameBoyButton.up: PadControl.up,
    GameBoyButton.down: PadControl.down,
    GameBoyButton.left: PadControl.left,
    GameBoyButton.right: PadControl.right,
    GameBoyButton.a: PadControl.a,
    GameBoyButton.b: PadControl.b,
    GameBoyButton.start: PadControl.start,
    GameBoyButton.select: PadControl.back,
  };
  static final choices = PadControl.values
      .where((c) => !_stickAlias.containsValue(c))
      .toList(growable: false);
  final _mapping = Map.of(_defaults);
  PadControl binding(GameBoyButton button) => _mapping[button]!;
  List<int?> _slots = const [];
  List<int> get connected => [
    for (var i = 0; i < _slots.length; i++)
      if (_slots[i] != null) i,
  ];
  int? slotFor(PadPlayer player) => connected.elementAtOrNull(player.index);
  int raw(int slot) => _slots[slot] ?? 0;
  Set<GameBoyButton> buttonsFor(PadPlayer player) {
    final slot = slotFor(player);
    if (slot == null) return {};
    final mask = raw(slot);
    return {
      for (final entry in _mapping.entries)
        if (mask & (entry.value.bit | (_stickAlias[entry.value]?.bit ?? 0)) !=
            0)
          entry.key,
    };
  }

  String? deviceError;
  String? storageError;
  StreamSubscription<List<int?>>? _subscription;
  bool _disposed = false;
  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_subscription != null) return;
    deviceError = null;
    _subscription = watch().listen(
      (slots) {
        _slots = slots;
        notifyListeners();
      },
      onError: (Object error) {
        debugPrint('Leitura XInput: $error');
        _slots = const [];
        deviceError = 'XInput indisponível neste Windows.';
        notifyListeners();
      },
    );
  }

  void _stop() {
    _subscription?.cancel();
    _subscription = null;
    _slots = const [];
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _stop();
  }

  Future<void>? _loading;
  Future<void> _writing = Future.value();
  Future<void> load() => _loading ??= _read();
  Future<void> _read() async {
    try {
      final saved = await (preferences ?? SharedPreferencesAsync())
          .getStringList(_key);
      if (saved == null) return;
      final controls = saved.map(PadControl.values.byName).toList();
      if (controls.length != _defaults.length ||
          controls.toSet().length != controls.length ||
          !controls.every(choices.contains)) {
        throw const FormatException();
      }
      for (final button in GameBoyButton.values) {
        _mapping[button] = controls[button.index];
      }
    } catch (error) {
      storageError = 'Falha ao ler os controles. Mapeamento padrão em uso.';
      debugPrint('Mapeamento XInput: $error');
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  // Swap an occupied binding so every logical button keeps a unique input.
  Future<void> bind(GameBoyButton button, PadControl control) async {
    await load();
    if (!choices.contains(control)) throw ArgumentError.value(control);
    final previous = binding(button);
    if (previous == control) return;
    for (final owner in GameBoyButton.values) {
      if (binding(owner) == control) _mapping[owner] = previous;
    }
    _mapping[button] = control;
    await _persist();
  }

  Future<void> restore() async {
    await load();
    _mapping.addAll(_defaults);
    await _persist();
  }

  Future<void> _persist() {
    final snapshot = [
      for (final button in GameBoyButton.values) binding(button).name,
    ];
    if (!_disposed) notifyListeners();
    return _writing = _writing.then((_) async {
      try {
        await (preferences ?? SharedPreferencesAsync()).setStringList(
          _key,
          snapshot,
        );
        storageError = null;
      } catch (error) {
        storageError =
            'Falha ao salvar o mapeamento do controle. Ativo nesta sessão.';
        debugPrint('Gravação XInput: $error');
      }
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    super.dispose();
  }
}
