import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'keyboard_bindings.dart';
export 'keyboard_bindings.dart' show GameBoyButton, KeyboardBindings;

/// Combines keyboard aliases and logical buttons into Libretro joypad state.
class GameBoyInputController extends ChangeNotifier {
  GameBoyInputController({KeyboardBindings? bindings})
    : _bindings = bindings ?? KeyboardBindings(),
      _ownsBindings = bindings == null {
    _bindings.addListener(_resetKeyboard);
  }
  final KeyboardBindings _bindings;
  final bool _ownsBindings;

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
    if (_bindings.buttonFor(key) == null) return false;
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
    if (_bindings.buttonFor(key) == null || _heldKeys.contains(key)) return;
    final before = pressedButtons;
    _heldKeys.add(key);
    if (!setEquals(before, pressedButtons)) notifyListeners();
  }

  void keyUp(LogicalKeyboardKey key) {
    if (!_heldKeys.contains(key)) return;
    final before = pressedButtons;
    _heldKeys.remove(key);
    if (!setEquals(before, pressedButtons)) notifyListeners();
  }

  /// Replaces the player's gamepad state while preserving held keys.
  void setDeviceButtons(Set<GameBoyButton> buttons) {
    if (setEquals(buttons, _deviceButtons)) return;
    final before = pressedButtons;
    _deviceButtons = {...buttons};
    if (!setEquals(before, pressedButtons)) notifyListeners();
  }

  int get joypadMask {
    final pressed = pressedButtons;
    var mask = 0;
    for (final entry in _libretroMap.entries) {
      if (pressed.contains(entry.value)) mask |= 1 << entry.key;
    }
    return mask;
  }

  int libretroState(int buttonId) =>
      pressedButtons.contains(_libretroMap[buttonId]) ? 1 : 0;

  void _resetKeyboard() {
    if (_heldKeys.isEmpty) return;
    _heldKeys.clear();
    notifyListeners();
  }

  void reset() {
    if (_heldKeys.isEmpty && _deviceButtons.isEmpty) return;
    _heldKeys.clear();
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
