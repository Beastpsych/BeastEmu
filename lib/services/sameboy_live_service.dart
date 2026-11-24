import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beastemu/services/rgba_frame_stream_decoder.dart';
import 'package:beastemu/services/sameboy_volume_control.dart';
import 'package:beastemu/services/sameboy_commands.dart';
import 'package:beastemu/services/sameboy_launch.dart';

import 'sameboy_link_protocol.dart';
import 'gba_cartridge.dart';
import 'gba_video.dart';

/// Sessão do SameBoy em um processo auxiliar no Windows.
/// O video usa TCP restrito a localhost; o teclado envia mascaras de 16 bits.
/// Nao sera a arquitetura definitiva para Android/distribuicao.
class SameBoyLiveService {
  SameBoyLiveService({this.linkRomPath, this.expectedRomHash});
  final String? expectedRomHash;
  final String? linkRomPath;
  ServerSocket? _server;
  Socket? _socket;
  Process? _process;
  StreamSubscription<Uint8List>? _subscription;
  StreamSubscription<String>? _outSubscription;
  StreamSubscription<String>? _errSubscription;
  bool _stopping = false;
  Future<void>? _startup;
  Future<void>? _shutdown;
  int _volume = 100;
  IOSink? _commands;
  String _logs = '';
  Completer<List<String?>>? _stateReply;
  int? _pendingCommand;
  bool cartridgeProtected = false;
  bool _gba = false;
  final _gbaVideo = GbaVideoDecoder();
  int get frameWidth => _gba
      ? _gbaVideo.width
      : linkRomPath == null
      ? 160
      : linkWidth;
  int get frameHeight => _gba ? _gbaVideo.height : 144;

  Future<List<String?>> stateCommand(int byte) {
    final commands = _commands;
    if (_gba ||
        linkRomPath != null ||
        !isStateCommand(byte) ||
        commands == null ||
        _stopping ||
        _stateReply != null) {
      throw StateError('Canal de estados indisponível.');
    }
    final pending = Completer<List<String?>>();
    _stateReply = pending;
    _pendingCommand = byte;
    try {
      commands.add([byte]);
    } catch (_) {
      _stateReply = null;
      rethrow;
    }
    // Keep the pending token on timeout: a late reply cannot be mistaken for a new request.
    return pending.future.timeout(const Duration(seconds: 8));
  }

  void _onOutput(String line) {
    if (!line.startsWith(stateReplyPrefix)) {
      _appendLog('$line\n');
      return;
    }
    final pending = _stateReply;
    if (pending == null) return;
    try {
      final data = jsonDecode(line.substring(stateReplyPrefix.length)) as Map;
      if (data['command'] != _pendingCommand) return;
      _stateReply = null;
      cartridgeProtected = data['protected'] == true;
      if (data['empty'] == true) throw const EmptyQuickSlot();
      if (data['error'] != null) throw StateError(data['error'].toString());
      pending.complete((data['slots'] as List?)?.cast<String?>() ?? []);
    } catch (error) {
      _stateReply = null;
      pending.completeError(error);
    }
  }

  Future<void> start({
    required String romPath,
    int volume = 100,
    required void Function(Uint8List) onFrame,
    required void Function(String) onError,
  }) {
    if (_startup != null || _stopping) {
      throw StateError('Esta sessão já foi usada.');
    }
    return _startup = _start(romPath, volume, onFrame, onError);
  }

  Future<void> _start(
    String romPath,
    int volume,
    void Function(Uint8List) onFrame,
    void Function(String) onError,
  ) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('A sessão GB/GBC requer Windows.');
    }
    final rom = File(romPath);
    if (!rom.existsSync()) throw StateError('ROM ausente: ${rom.path}');
    final core = coreForPath(romPath);
    if (core == null) {
      throw const FormatException('Extensão de cartucho inválida.');
    }
    _gba = core == CartridgeCore.mgba;
    if (linkRomPath != null &&
        (_gba || coreForPath(linkRomPath!) != CartridgeCore.sameBoy)) {
      throw UnsupportedError('O Link Cable requer dois cartuchos GB/GBC.');
    }
    final launch = SameBoyLaunch.resolve(
      _gba ? SameBoyHelper.gba : SameBoyHelper.live,
    );
    _volume = volume.clamp(0, 100);
    final partner = linkRomPath == null ? null : File(linkRomPath!);
    if (partner != null && !partner.existsSync()) {
      throw StateError('ROM do jogador 2 ausente.');
    }
    final parser = RgbaFrameStreamDecoder(
      bytesPerFrame: partner == null
          ? RgbaFrameStreamDecoder.frameSize
          : linkWidth * linkHeight * 4,
    );
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      if (_stopping) return;
      final launchVolume = _volume;
      _process = await Process.start(
        launch.executable,
        [
          ...launch.prefix,
          if (partner != null) linkLaunchFlag,
          rom.absolute.path,
          if (partner != null) partner.absolute.path,
          _server!.port.toString(),
        ],
        workingDirectory: launch.root.path,
        environment: {
          if (Platform.environment['LOCALAPPDATA'] case final local?)
            'LOCALAPPDATA': '$local/BeastEmu-GBA-Dev',
          sameBoyCommandEnvironment: !_gba && partner == null ? '1' : '0',
          expectedRomEnvironment: expectedRomHash ?? '',
          sameBoyVolumeEnvironment: launchVolume.toString(),
          'BEASTEMU_AUDIO_DLL':
              '${File(Platform.resolvedExecutable).parent.path}/beastemu_audio.dll',
        },
        runInShell: launch.usesShell,
      );
      final commands = _process!.stdin;
      _commands = commands;
      unawaited(
        commands.done.then<void>(
          (_) {},
          onError: (Object error) {
            if (identical(_commands, commands)) _commands = null;
            if (!_stopping) _appendLog('Canal de volume encerrado: $error');
          },
        ),
      );
      if (_speed != 1) commands.add([speedNormal + _speed - 1]);
      if (_volume != launchVolume) _sendVolume();
      _outSubscription = _process!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_onOutput);
      _errSubscription = _process!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((text) => _appendLog(text));
      unawaited(
        _process!.exitCode.then((code) {
          if (!_stopping) {
            onError(
              '${_gba ? "mGBA" : "SameBoy"} encerrou (código $code). '
              'Últimas mensagens:\n$_logs',
            );
          }
        }),
      );
      final connection = _server!.first;
      final ready = _gba
          ? Future.any<Socket>([
              connection,
              _process!.exitCode.then<Socket>(
                (code) => throw StateError('mGBA encerrou ($code). $_logs'),
              ),
            ])
          : connection;
      _socket = await ready.timeout(const Duration(seconds: 15));
      if (_stopping) {
        // The dialog closed while Dart was starting. Release the child's
        // connection so it can finish restoring/flushing and drop its lock.
        _socket!.destroy();
        _socket = null;
        _closeCommands();
        return;
      }
      _socket!.setOption(SocketOption.tcpNoDelay, true);
      _subscription = _socket!.listen(
        (data) {
          if (!_gba) {
            parser.add(data, onFrame);
            return;
          }
          try {
            _gbaVideo.add(data, onFrame);
          } on FormatException catch (error) {
            onError(error.message);
            _socket?.destroy();
          }
        },
        onError: (Object error) {
          if (!_stopping) onError('Falha na transmissão de video: $error');
        },
        onDone: () {
          if (!_stopping) {
            onError(
              'Transmissão de video encerrada. '
              '$_logs',
            );
          }
        },
      );
    } catch (error) {
      _stopping = true;
      await _release();
      rethrow;
    } finally {
      await _server?.close();
      _server = null;
    }
  }

  void _appendLog(String chunk) {
    final text = _logs + chunk;
    _logs = text.length > 6000 ? text.substring(text.length - 6000) : text;
  }

  void setVolume(int percent) {
    final value = percent.clamp(0, 100);
    if (_volume == value) return;
    _volume = value;
    _sendVolume();
  }

  int _speed = 1;
  void setSpeed(int speed) {
    RangeError.checkValueInInterval(speed, 1, 4, 'speed');
    if (_gba || linkRomPath != null || _speed == speed || _stopping) return;
    _speed = speed;
    _commands?.add([speedNormal + speed - 1]);
  }

  void _sendVolume() {
    if (_stopping) return;
    _commands?.add([_volume]);
  }

  void _closeCommands() {
    _commands
        ?.close()
        .ignore(); // An exiting helper may already have closed stdin.
    _commands = null;
  }

  /// IDs Libretro da porta 0, dispositivo RETRO_DEVICE_JOYPAD.
  void sendMask(int mask) {
    final socket = _socket;
    if (socket == null || _stopping || linkRomPath != null) return;
    socket.add([mask & 0xff, (mask >> 8) & 0xff]);
  }

  void sendLinkMasks(int first, int second) {
    final socket = _socket;
    if (socket == null || _stopping || linkRomPath == null) return;
    socket.add([first & 255, first >> 8, second & 255, second >> 8]);
  }

  Future<void> stop() => _shutdown ??= _stop();

  Future<void> _stop() async {
    _stopping = true;
    // A late connection still needs to be closed before the helper can flush.
    try {
      await _startup;
    } catch (_) {
      // Startup reports its diagnostic to the caller and releases the child.
    }
    try {
      await _release();
    } on TimeoutException {
      // Both cartridges are still owned by this helper until it exits.
      if (linkRomPath != null) _shutdown = null;
      rethrow;
    }
  }

  Future<void> _release() async {
    _closeCommands();
    await _subscription?.cancel();
    _socket?.destroy();
    _socket = null;
    final process = _process;
    int? exitCode;
    if (process != null) {
      try {
        // The helper flushes the cartridge to user storage before exiting.
        exitCode = await process.exitCode.timeout(const Duration(seconds: 15));
      } on TimeoutException {
        throw TimeoutException(
          'O auxiliar ainda não confirmou o encerramento. '
          'A gravação do cartucho pode estar em andamento.',
        );
      }
    }
    await _outSubscription?.cancel();
    await _errSubscription?.cancel();
    _process = null;
    if (linkRomPath != null && exitCode != null && exitCode != 0) {
      throw StateError(
        'O auxiliar Link Cable encerrou com código $exitCode. $_logs',
      );
    }
  }
}
