import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:beastemu/core/theme.dart';
import 'package:beastemu/services/gba_cartridge.dart';
import 'package:beastemu/services/xinput.dart' show PadControl;
import 'package:beastemu/services/emulation_settings.dart';
import 'package:beastemu/services/sameboy_commands.dart';
import 'package:beastemu/widgets/emulation_settings_panel.dart';
import 'package:beastemu/widgets/gameboy_viewport.dart';
import 'package:beastemu/services/gameboy_input_controller.dart';
import 'package:beastemu/services/keyboard_bindings.dart' show EmulatorShortcut;
import 'package:beastemu/services/gamepads.dart';
import 'package:beastemu/services/sameboy_link_protocol.dart';
import 'package:beastemu/services/sameboy_live_service.dart';
import 'package:beastemu/widgets/state_slots_dialog.dart';

/// Sessão de emulação GB/GBC no Windows.
class SameBoyLiveDialog extends StatefulWidget {
  const SameBoyLiveDialog({
    super.key,
    required this.settings,
    required this.bindings,
    required this.romPath,
    this.expectedRomHash,
    required this.gameTitle,
    this.service,
    this.gamepads,
    this.partner,
    this.onFirstFrame,
  });

  final SameBoyLiveService? service;
  final Gamepads? gamepads;
  final ({String path, String title})? partner;
  final VoidCallback? onFirstFrame;
  final EmulationSettings settings;
  final KeyboardBindings bindings;
  final String romPath;
  final String? expectedRomHash;
  final String gameTitle;

  @override
  State<SameBoyLiveDialog> createState() => _SameBoyLiveDialogState();
}

class _SameBoyLiveDialogState extends State<SameBoyLiveDialog> {
  bool get _gba => coreForPath(widget.romPath) == CartridgeCore.mgba;
  bool get _singleSameBoy => !_dual;
  bool get _singleSession => !_dual;
  bool get _dual => widget.partner != null;
  late final _service =
      widget.service ??
      SameBoyLiveService(
        linkRomPath: widget.partner?.path,
        expectedRomHash: widget.expectedRomHash,
      );
  static const _window = MethodChannel('beastemu/window');
  bool _fullscreen = false;
  bool _changingWindow = false;
  late final _input = GameBoyInputController(
    bindings: widget.bindings,
    gba: _gba,
  );
  late final _second = _dual
      ? GameBoyInputController(bindings: widget.bindings)
      : null;
  late final AppLifecycleListener _lifecycle;
  final _focus = FocusNode(debugLabel: 'Tela SameBoy');
  ui.Image? _image;
  bool _decoding = false;
  int _selectedSpeed = 1;
  bool _holdingSpeed = false;
  int get _effectiveSpeed => _holdingSpeed ? 4 : _selectedSpeed;
  bool _windowActive = true;
  final _waitForNeutral = [true, true];
  final _padSlots = <int?>[null, null];

  void _readPad() {
    final pads = widget.gamepads;
    if (pads == null ||
        !_windowActive ||
        !_focus.hasPrimaryFocus ||
        _closing ||
        _error != null) {
      return;
    }
    final keyboardAndOnePad = _dual && pads.connected.length == 1;
    void apply(
      int index,
      GameBoyInputController controller,
      PadPlayer? source,
    ) {
      final slot = source == null ? null : pads.slotFor(source);
      if (slot != _padSlots[index]) {
        _padSlots[index] = slot;
        _waitForNeutral[index] = true;
        controller.setDeviceButtons({});
      }
      if (slot == null || source == null) return;
      if (_waitForNeutral[index]) {
        if (pads.raw(slot) != 0) return;
        _waitForNeutral[index] = false;
      }
      final raw = pads.raw(slot);
      final shoulders =
          (raw & PadControl.lb.bit != 0 ? 1 << 10 : 0) |
          (raw & PadControl.rb.bit != 0 ? 1 << 11 : 0);
      controller.setDeviceButtons(
        pads.buttonsFor(source),
        shoulders: _gba ? shoulders : 0,
      );
    }

    apply(0, _input, keyboardAndOnePad ? null : PadPlayer.one);
    final second = _second;
    if (second != null) {
      apply(1, second, keyboardAndOnePad ? PadPlayer.one : PadPlayer.two);
    }
  }

  void _holdSpeed(bool held) {
    if (held == _holdingSpeed) return;
    setState(() => _holdingSpeed = held);
    _service.setSpeed(_effectiveSpeed);
  }

  void _cycleSpeed() {
    setState(() => _selectedSpeed = _selectedSpeed % 4 + 1);
    _service.setSpeed(_effectiveSpeed);
  }

  void _releaseInput() {
    _waitForNeutral.fillRange(0, 2, true);
    _input.reset();
    _second?.reset();
    _holdSpeed(false);
  }

  bool _closing = false;
  Future<void>? _stopTask;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_settingsChanged);
    _windowActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _windowActive = state == AppLifecycleState.resumed;
        if (_windowActive) {
          _readPad();
        } else {
          _releaseInput();
        }
      },
    );
    _focus.addListener(_gameFocusChanged);
    _input.addListener(_updateButtons);
    _second?.addListener(_updateButtons);
    widget.gamepads?.addListener(_readPad);
    unawaited(_start());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  Future<void> _start() async {
    try {
      await _service.start(
        romPath: widget.romPath,
        volume: widget.settings.effectiveVolume,
        onFrame: _showFrame,
        onError: _setError,
      );
      if (mounted) _updateButtons();
    } catch (error) {
      _setError(error.toString());
    }
  }

  void _settingsChanged() {
    _service.setVolume(widget.settings.effectiveVolume);
    setState(() {});
  }

  Future<void> _showSettings() async {
    _releaseInput();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configurações'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: EmulationSettingsPanel(settings: widget.settings),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Voltar ao jogo'),
          ),
        ],
      ),
    );
    if (mounted) _focus.requestFocus();
  }

  String? _feedback;
  bool _quickBusy = false;
  Future<void> _quickState(bool save) async {
    if (_quickBusy ||
        !_singleSession ||
        _image == null ||
        _error != null ||
        _closing) {
      return;
    }
    _quickBusy = true;
    try {
      await _service.stateCommand(save ? quickSave : quickLoad);
      if (mounted) {
        _showFeedback(
          'Estado rápido ${save ? "salvo" : "carregado"}: ${widget.gameTitle}',
        );
      }
    } on EmptyQuickSlot {
      if (mounted) {
        _showFeedback('Nenhum estado rápido para ${widget.gameTitle}.');
      }
    } catch (error) {
      if (mounted) _showFeedback('Falha no estado rápido: $error');
    } finally {
      _quickBusy = false;
    }
  }

  Timer? _feedbackTimer;

  Future<void> _showStates(StateSlotAction action) async {
    _releaseInput();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StateSlotsDialog(
        service: _service,
        action: action,
        gameTitle: widget.gameTitle,
      ),
    );
    if (mounted) {
      if (result != null) _showFeedback(result);
      _focus.requestFocus();
    }
  }

  void _showFeedback(String message) {
    _feedbackTimer?.cancel();
    setState(() => _feedback = message);
    _feedbackTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  Future<void> _setFullscreen(bool enabled) async {
    if (_changingWindow || enabled == _fullscreen) return;
    setState(() => _changingWindow = true);
    try {
      final applied = await _window.invokeMethod<bool>(
        'setFullscreen',
        enabled,
      );
      if (mounted) setState(() => _fullscreen = applied == true);
    } on PlatformException catch (error) {
      if (mounted) {
        _showFeedback(
          'Falha ao alterar a tela cheia. ${error.message ?? error.code}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _changingWindow = false);
        _focus.requestFocus();
      }
    }
  }

  Future<void> _stopOnce() => _stopTask ??= _service.stop();

  Future<void> _leaveGame() async {
    if (_changingWindow || _closing) return;
    if (_fullscreen) await _setFullscreen(false);
    if (!mounted || _fullscreen || _closing) return;
    _releaseInput();
    setState(() => _closing = true);
    try {
      await _stopOnce();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _closing = false;
        _error = 'Falha ao encerrar a sessão: $error';
      });
      _stopTask = (_dual || _gba) && error is TimeoutException
          ? null
          : Future<void>.value();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _gameFocusChanged() {
    if (_focus.hasPrimaryFocus) {
      _readPad();
    } else {
      _releaseInput();
    }
  }

  void _updateButtons() {
    final second = _second;
    if (second == null) {
      _service.sendMask(_input.joypadMask);
    } else {
      _service.sendLinkMasks(_input.joypadMask, second.joypadMask);
    }
  }

  void _setError(String message) {
    if (mounted && !_closing && _error == null) {
      setState(() {
        _error = message;
      });
    }
  }

  void _showFrame(Uint8List rgba) {
    if (!mounted || _closing || _decoding || _error != null) return;
    _decoding = true;
    try {
      ui.decodeImageFromPixels(
        rgba,
        _gba
            ? _service.frameWidth
            : _dual
            ? linkWidth
            : 160,
        _gba ? _service.frameHeight : 144,
        ui.PixelFormat.rgba8888,
        (ui.Image image) {
          _decoding = false;
          if (!mounted || _closing || _error != null) {
            image.dispose();
            return;
          }
          final previous = _image;
          if (previous == null) widget.onFirstFrame?.call();
          setState(() {
            _image = image;
          });
          if (previous != null) {
            // Libera depois do frame para nao descartar enquanto e pintado.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              previous.dispose();
            });
          }
        },
      );
    } catch (error) {
      _decoding = false;
      _setError('Erro ao desenhar frame RGBA: $error');
    }
  }

  @override
  void dispose() {
    if (_fullscreen || _changingWindow) {
      _window.invokeMethod<bool>('setFullscreen', false).ignore();
    }
    widget.settings.removeListener(_settingsChanged);
    widget.gamepads?.removeListener(_readPad);
    _input.reset();
    _input.removeListener(_updateButtons);
    _second?.reset();
    _second?.removeListener(_updateButtons);
    _second?.dispose();
    _focus.removeListener(_gameFocusChanged);
    _lifecycle.dispose();
    _input.dispose();
    _feedbackTimer?.cancel();
    _focus.dispose();
    _stopOnce().ignore();
    _image?.dispose();
    super.dispose();
  }

  Widget _display() {
    if (!_closing && _error == null && _image != null) {
      return RawImage(
        image: _image,
        fit: BoxFit.contain,
        filterQuality: widget.settings.smooth
            ? FilterQuality.low
            : FilterQuality.none,
      );
    }
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_closing && _error != null) ...[
              Text(
                _gba ? 'Falha na sessão do mGBA' : 'Falha na sessão do SameBoy',
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Detalhes da sessão'),
                    content: SingleChildScrollView(
                      child: SelectableText(_error!),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Voltar'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Detalhes'),
              ),
            ] else ...[
              const CircularProgressIndicator(color: beastRed),
              const SizedBox(height: 12),
              Text(
                _closing
                    ? 'Encerrando sessão…'
                    : _gba
                    ? 'Iniciando mGBA…'
                    : 'Iniciando SameBoy…',
              ),
            ],
          ],
        ),
      ),
    );
  }

  KeyEventResult _gameKey(FocusNode node, KeyEvent event) {
    if (_closing) return KeyEventResult.handled;
    if (!node.hasPrimaryFocus ||
        !_windowActive ||
        ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final down =
        event is KeyDownEvent &&
        !event.synthesized &&
        !KeyboardBindings.shortcutModifierPressed;
    if (key == LogicalKeyboardKey.escape && (_fullscreen || _changingWindow)) {
      if (down) unawaited(_setFullscreen(false));
      return KeyEventResult.handled;
    }
    final action = widget.bindings.actionFor(key);
    if (action == null) {
      return _input.handleKeyEvent(event)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (action == EmulatorShortcut.holdSpeed && event is KeyUpEvent) {
      _holdSpeed(false);
    }
    if (down) {
      switch (action) {
        case EmulatorShortcut.quickSave:
        case EmulatorShortcut.quickLoad:
          if (_singleSession) {
            unawaited(_quickState(action == EmulatorShortcut.quickSave));
          }
        case EmulatorShortcut.mute:
          final muted = !widget.settings.muted;
          unawaited(widget.settings.setMuted(muted));
          _showFeedback(muted ? 'Áudio silenciado.' : 'Áudio ativado.');
        case EmulatorShortcut.cycleSpeed:
          if (_singleSameBoy) _cycleSpeed();
        case EmulatorShortcut.holdSpeed:
          if (_singleSameBoy) _holdSpeed(true);
        case EmulatorShortcut.fullscreen:
          unawaited(_setFullscreen(!_fullscreen));
      }
    }
    return KeyEventResult.handled;
  }

  Widget _toolbar() {
    final fullscreenKey = widget.bindings.shortcutKey(
      EmulatorShortcut.fullscreen,
    );
    final shortcutHint = fullscreenKey == null
        ? ''
        : ' (${fullscreenKey.keyLabel})';
    return LayoutBuilder(
      builder: (context, bounds) {
        final roomForIcons = bounds.maxWidth >= 720;
        return TextButtonTheme(
          data: TextButtonThemeData(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(40, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    _dual
                        ? 'Link Cable Local · Experimental'
                        : widget.gameTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_singleSameBoy)
                  Semantics(
                    label: 'Velocidade atual',
                    child: Text(
                      '$_effectiveSpeed×',
                      style: TextStyle(
                        color: _effectiveSpeed > 1
                            ? Colors.redAccent
                            : Colors.white70,
                      ),
                    ),
                  ),
                if (_singleSession)
                  for (final action in StateSlotAction.values)
                    TextButton.icon(
                      onPressed: _closing || _image == null || _error != null
                          ? null
                          : () => _showStates(action),
                      icon: !roomForIcons
                          ? null
                          : Icon(
                              action == StateSlotAction.save
                                  ? Icons.save_outlined
                                  : Icons.restore,
                            ),
                      label: Text(action.label),
                    ),
                if (_singleSameBoy)
                  Tooltip(
                    message: 'Selecionar ${_selectedSpeed % 4 + 1}×',
                    child: Semantics(
                      toggled: _effectiveSpeed > 1,
                      child: TextButton.icon(
                        onPressed: _closing
                            ? null
                            : () {
                                _focus.requestFocus();
                                _cycleSpeed();
                              },
                        icon: roomForIcons
                            ? const Icon(Icons.fast_forward)
                            : null,
                        label: const Text('Acelerar'),
                      ),
                    ),
                  ),
                Tooltip(
                  message: _fullscreen
                      ? 'Sair da tela cheia$shortcutHint'
                      : 'Tela cheia$shortcutHint',
                  child: TextButton.icon(
                    onPressed: _closing || _changingWindow
                        ? null
                        : () => _setFullscreen(!_fullscreen),
                    icon: !roomForIcons
                        ? null
                        : Icon(
                            _fullscreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                          ),
                    label: Text(_fullscreen ? 'Modo janela' : 'Tela cheia'),
                  ),
                ),
                IconButton(
                  tooltip: 'Configurações do jogo',
                  onPressed: _closing ? null : _showSettings,
                  icon: const Icon(Icons.tune),
                ),
                if (_gba)
                  IconButton(
                    tooltip: widget.settings.muted
                        ? 'Ativar áudio'
                        : 'Silenciar áudio',
                    onPressed: _closing
                        ? null
                        : () {
                            unawaited(
                              widget.settings.setMuted(!widget.settings.muted),
                            );
                            _focus.requestFocus();
                          },
                    icon: Icon(
                      widget.settings.muted
                          ? Icons.volume_off
                          : Icons.volume_up,
                    ),
                  ),
                Tooltip(
                  message: 'Fechar',
                  child: TextButton.icon(
                    onPressed: _closing || _changingWindow ? null : _leaveGame,
                    icon: roomForIcons ? const Icon(Icons.close) : null,
                    label: const Text('Sair'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leaveGame());
      },
      child: Dialog(
        insetPadding: EdgeInsets.all(_fullscreen ? 0 : 10),
        shape: _fullscreen ? const RoundedRectangleBorder() : null,
        constraints: const BoxConstraints.expand(),
        backgroundColor: beastPanel,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: double.infinity),
          child: Padding(
            padding: EdgeInsets.all(_fullscreen ? 0 : 8),
            child: Focus(
              focusNode: _focus,
              autofocus: true,
              onKeyEvent: _gameKey,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _focus.requestFocus,
                child: Column(
                  mainAxisSize: _fullscreen
                      ? MainAxisSize.max
                      : MainAxisSize.min,
                  children: [
                    _toolbar(),
                    if (_gba)
                      Text(
                        'GBA · ${_service.gbaSaveStatus} · L/R: Q/E ou LB/RB',
                        textAlign: TextAlign.center,
                      ),
                    if (widget.partner case final partner?)
                      Row(
                        children: [
                          for (final label in [
                            'Jogador 1 · ${widget.gameTitle}',
                            'Jogador 2 · ${partner.title}',
                          ])
                            Expanded(
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    if (_service.cartridgeProtected)
                      const Text(
                        'Cartucho protegido nesta sessão · use os slots para salvar',
                      ),
                    if (_feedback != null)
                      Semantics(liveRegion: true, child: Text(_feedback!)),
                    Expanded(
                      child: GameBoyViewport(
                        nativeWidth:
                            _image?.width ??
                            (_gba
                                ? 240
                                : _dual
                                ? linkWidth
                                : 160),
                        nativeHeight: _image?.height ?? (_gba ? 160 : 144),
                        scale: widget.settings.scale,
                        child: _display(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
