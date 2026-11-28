import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'keyboard_bindings.dart';
export 'keyboard_bindings.dart' show GameBoyButton, KeyboardBindings;

/// Combines keyboard aliases and logical buttons into Libretro joypad state.
class GameBoyInputController extends ChangeNotifier {
  GameBoyInputController({KeyboardBindings? bindings, this.gba = false})
    : _bindings = bindings ?? KeyboardBindings(),
      _ownsBindings = bindings == null {
    _bindings.addListener(_resetKeyboard);
  }
  final KeyboardBindings _bindings;
  final bool _ownsBindings;
  final bool gba;
  int _padShoulders = 0;
  int _shoulder(LogicalKeyboardKey key) {
    if (!gba ||
        _bindings.buttonFor(key) != null ||
        _bindings.actionFor(key) != null) {
      return 0;
    }
    if (key == LogicalKeyboardKey.keyQ) return 1 << 10;
    if (key == LogicalKeyboardKey.keyE) return 1 << 11;
    return 0;
  }

  static const Map<int, GameBoyButton> _libretroMap = {
    0: GameBoyButton.b,
    2: GameBoyButton.select,
    3: GameBoyButton.start,
    4: GameBoyButton.up,
    5: GameBoyButton.down,
    6: GameBoyButton.left,
    7: GameBoyButton.right,
    8: GameBoyButton.a,
  };

  final Set<LogicalKeyboardKey> _heldKeys = {};
  Set<GameBoyButton> _deviceButtons = {};

  Set<GameBoyButton> get pressedButtons => {
    ..._deviceButtons,
    for (final key in _heldKeys) ?_bindings.buttonFor(key),
  };

  bool isPressed(GameBoyButton button) => pressedButtons.contains(button);

  bool handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    if (_bindings.buttonFor(key) == null && _shoulder(key) == 0) return false;
    if (event is KeyUpEvent) {
      keyUp(key);
    } else if (KeyboardBindings.shortcutModifierPressed) {
      return false;
    } else if (event is KeyDownEvent || event is KeyRepeatEvent) {
      keyDown(key);
    }
    return true;
  }

  void keyDown(LogicalKeyboardKey key) {
    if ((_bindings.buttonFor(key) == null && _shoulder(key) == 0) ||
        _heldKeys.contains(key)) {
      return;
    }
    final before = joypadMask;
    _heldKeys.add(key);
    if (before != joypadMask) notifyListeners();
  }

  void keyUp(LogicalKeyboardKey key) {
    if (!_heldKeys.contains(key)) return;
    final before = joypadMask;
    _heldKeys.remove(key);
    if (before != joypadMask) notifyListeners();
  }

  /// Replaces the player's gamepad state while preserving held keys.
  void setDeviceButtons(Set<GameBoyButton> buttons, {int shoulders = 0}) {
    if (setEquals(buttons, _deviceButtons) && shoulders == _padShoulders) {
      return;
    }
    final before = joypadMask;
    _padShoulders = gba ? shoulders : 0;
    _deviceButtons = {...buttons};
    if (before != joypadMask) notifyListeners();
  }

  int get joypadMask {
    final pressed = pressedButtons;
    var mask = _padShoulders;
    if (gba) {
      for (final key in _heldKeys) {
        mask |= _shoulder(key);
      }
    }
    for (final entry in _libretroMap.entries) {
      if (pressed.contains(entry.value)) mask |= 1 << entry.key;
    }
    return mask;
  }

  int libretroState(int buttonId) =>
      buttonId >= 0 && buttonId < 16 ? (joypadMask >> buttonId) & 1 : 0;

  void _resetKeyboard() {
    if (_heldKeys.isEmpty) return;
    _heldKeys.clear();
    notifyListeners();
  }

  void reset() {
    if (_heldKeys.isEmpty && _deviceButtons.isEmpty && _padShoulders == 0) {
      return;
    }
    _heldKeys.clear();
    _padShoulders = 0;
    _deviceButtons.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _bindings.removeListener(_resetKeyboard);
    if (_ownsBindings) _bindings.dispose();
    super.dispose();
  }
}
