import 'dart:async';
import 'dart:ffi';
import 'dart:convert';

import 'package:beastemu/services/sameboy_commands.dart';
import 'sameboy_states.dart';
import 'sameboy_link_subsystem.dart';
import 'package:beastemu/services/sameboy_link_protocol.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:crypto/crypto.dart';
import 'package:beastemu/services/libretro_frame_converter.dart';
import 'package:beastemu/services/sameboy_volume_control.dart';

import 'cartridge_save.dart';
import 'sameboy_audio_output.dart';

// BeastEmu Etapa 05.1: teste experimental Windows.
// Isola o SameBoy em outro processo e envia frames RGBA via TCP local.
// Porta TCP somente em 127.0.0.1; nao e uma API de rede publica.
// Audio PCM local ao processo auxiliar.

final class RetroGameInfo extends Struct {
  external Pointer<Utf8> path;
  external Pointer<Void> data;

  @Size()
  external int size;

  external Pointer<Utf8> meta;
}

final class RetroGameGeometry extends Struct {
  @Uint32()
  external int baseWidth;

  @Uint32()
  external int baseHeight;

  @Uint32()
  external int maxWidth;

  @Uint32()
  external int maxHeight;

  @Float()
  external double aspectRatio;
}

final class RetroSystemTiming extends Struct {
  @Double()
  external double fps;

  @Double()
  external double sampleRate;
}

final class RetroSystemAvInfo extends Struct {
  external RetroGameGeometry geometry;
  external RetroSystemTiming timing;
}

typedef EnvironmentNative = Uint8 Function(Uint32, Pointer<Void>);
typedef VideoNative = Void Function(Pointer<Void>, Uint32, Uint32, Size);
typedef AudioSampleNative = Void Function(Int16, Int16);
typedef AudioBatchNative = Size Function(Pointer<Int16>, Size);
typedef InputPollNative = Void Function();
typedef InputStateNative = Int16 Function(
    Uint32, Uint32, Uint32, Uint32);

typedef SetEnvironmentNative = Void Function(
    Pointer<NativeFunction<EnvironmentNative>>);
typedef SetVideoNative = Void Function(
    Pointer<NativeFunction<VideoNative>>);
typedef SetAudioSampleNative = Void Function(
    Pointer<NativeFunction<AudioSampleNative>>);
typedef SetAudioBatchNative = Void Function(
    Pointer<NativeFunction<AudioBatchNative>>);
typedef SetInputPollNative = Void Function(
    Pointer<NativeFunction<InputPollNative>>);
typedef SetInputStateNative = Void Function(
    Pointer<NativeFunction<InputStateNative>>);

typedef SetEnvironmentDart = void Function(
    Pointer<NativeFunction<EnvironmentNative>>);
typedef SetVideoDart = void Function(
    Pointer<NativeFunction<VideoNative>>);
typedef SetAudioSampleDart = void Function(
    Pointer<NativeFunction<AudioSampleNative>>);
typedef SetAudioBatchDart = void Function(
    Pointer<NativeFunction<AudioBatchNative>>);
typedef SetInputPollDart = void Function(
    Pointer<NativeFunction<InputPollNative>>);
typedef SetInputStateDart = void Function(
    Pointer<NativeFunction<InputStateNative>>);

typedef LifecycleNative = Void Function();
typedef LifecycleDart = void Function();
typedef LoadGameNative = Uint8 Function(Pointer<RetroGameInfo>);
typedef LoadGameDart = int Function(Pointer<RetroGameInfo>);
typedef GetAvInfoNative = Void Function(Pointer<RetroSystemAvInfo>);
typedef GetAvInfoDart = void Function(Pointer<RetroSystemAvInfo>);

// retro_run executa um quadro de emulacao a cada chamada.
typedef RetroRunNative = Void Function();
typedef RetroRunDart = void Function();

const _width = 160;
const _height = 144;

Future<void> main(List<String> args) async {
  final dual = args.length == 4 && args.first == linkLaunchFlag;
  if (!Platform.isWindows || (!dual && args.length != 2)) {
    stderr.writeln('Uso: stream_sameboy <rom> <porta> ou '
        'stream_sameboy $linkLaunchFlag <rom1> <rom2> <porta>');
    exitCode = 2;
    return;
  }

  final roms = dual ? [File(args[1]), File(args[2])] : [File(args.first)];
  final core = File('cores/windows/sameboy_libretro.dll');
  final port = int.tryParse(args.last);
  bool validRom(File rom) {
    final path = rom.path.toLowerCase();
    return (path.endsWith('.gb') || path.endsWith('.gbc')) && rom.existsSync();
  }
  if (port == null || port <= 0 || port > 65535 ||
      !core.existsSync() || !roms.every(validRom)) {
    stderr.writeln('ROM GB/GBC, DLL SameBoy ou porta invalida.');
    exitCode = 2;
    return;
  }
  final cartridges = await Future.wait(roms.map((rom) => rom.readAsBytes()));
  final romIdentity = sha256.convert(cartridges.first);
  final expected = Platform.environment[expectedRomEnvironment];
  if (!dual && expected != null && expected.isNotEmpty &&
      expected != romIdentity.toString()) {
    stderr.writeln('A cópia da ROM difere da entrada da biblioteca. Sessão cancelada.');
    exitCode = 2;
    return;
  }
  if (cartridges.any((bytes) => bytes.length < 0x150)) {
    stderr.writeln('ROM pequena demais.');
    exitCode = 2;
    return;
  }

  Socket? socket;
  NativeCallable<EnvironmentNative>? envCb;
  NativeCallable<VideoNative>? videoCb;
  NativeCallable<AudioSampleNative>? audioCb;
  NativeCallable<AudioBatchNative>? batchCb;
  NativeCallable<InputPollNative>? pollCb;
  NativeCallable<InputStateNative>? stateCb;
  final arena = Arena();
  final link = dual ? LinkSubsystem(arena) : null;
  LifecycleDart? deinit;
  LifecycleDart? unload;
  bool initialized = false;
  bool loaded = false;
  bool running = true;
  final input = JoypadPackets(dual: dual);
  int pixelFormat = 0;
  CartridgeSave? cartridgeSave;
  final saves = <CartridgeSave>[];
  SameBoyAudioOutput? audioOutput;
  final launchVolume = Platform.environment[sameBoyVolumeEnvironment];
  var volume = (int.tryParse(launchVolume ?? '') ?? 100).clamp(0, 100);
  StreamSubscription<List<int>>? volumeCommands;
  int frameNumber = 0;
  var speed = 1;
  var videoPending = false;
  final offerTarget = Platform.environment['BEASTEMU_AUDIO_BASELINE'] != '1';
  var targetQueries = 0;
  var phase = 'registration';
  var queryPhase = 'none';
  var audioFrames = 0;
  var batches = 0;
  var singles = 0;
  Uint8List? rawFrame;
  int rawWidth = 0;
  int rawHeight = 0;
  int rawPitch = 0;
  int rawFormat = 0;

  try {
    socket = await Socket.connect(InternetAddress.loopbackIPv4, port)
        .timeout(const Duration(seconds: 10));
    socket.setOption(SocketOption.tcpNoDelay, true);
    // The window can close while a video write is pending. Observe the sink
    // error too, so a peer reset still reaches the cartridge's final flush.
    unawaited(socket.done.then<void>((_) { running = false; },
        onError: (Object _) { running = false; }));
    socket.listen(input.add, onDone: () => running = false,
        onError: (_) => running = false);

    final library = DynamicLibrary.open(core.absolute.path);
    envCb = NativeCallable<EnvironmentNative>.isolateLocal(
      (int command, Pointer<Void> data) {
        switch (command) {
          case const (0x10000 | 81): // RETRO_ENVIRONMENT_GET_TARGET_SAMPLE_RATE
            targetQueries++;
            queryPhase = phase;
            if (!offerTarget || data.address == 0) return 0;
            data.cast<Uint32>().value = 48000;
            return 1;
          case 3: // GET_CAN_DUPE
            if (data.address == 0) return 0;
            data.cast<Uint8>().value = 0;
            return 1;
          case 10: // SET_PIXEL_FORMAT
            if (data.address == 0) return 0;
            final selected = data.cast<Int32>().value;
            if (selected == 0 || selected == 1 || selected == 2) {
              pixelFormat = selected;
              return 1;
            }
            return 0;
          case 17: // GET_VARIABLE_UPDATE
            if (data.address == 0) return 0;
            data.cast<Uint8>().value = 0;
            return 1;
          case 52: // GET_CORE_OPTIONS_VERSION
            if (data.address == 0) return 0;
            data.cast<Uint32>().value = 0;
            return 1;
          default:
            return link?.environment(command, data) ?? 0;
        }
      }, exceptionalReturn: 0,
    );
    videoCb = NativeCallable<VideoNative>.isolateLocal(
      (Pointer<Void> data, int width, int height, int pitch) {
        // Enviar um quadro a cada dois para reduzir trabalho no Flutter.
        if (videoPending || frameNumber % (2 * speed) != 0 || data.address == 0 ||
            width != (dual ? linkWidth : _width) || height != _height) {
          return;
        }
        final bpp = pixelFormat == 1 ? 4 : 2;
        if (pitch < width * bpp || pitch > 4096) {
          return;
        }
        rawFrame = Uint8List.fromList(data.cast<Uint8>()
            .asTypedList(pitch * height));
        rawWidth = width;
        rawHeight = height;
        rawPitch = pitch;
        rawFormat = pixelFormat;
      },
    );
    audioCb = NativeCallable<AudioSampleNative>.isolateLocal(
      (int left, int right) {
        singles++;
        audioFrames++;
        if (speed == 1) audioOutput?.sample(left, right);
      },
    );
    batchCb = NativeCallable<AudioBatchNative>.isolateLocal(
      (Pointer<Int16> data, int frames) {
        batches++;
        audioFrames += frames;
        // SameBoy retries unconsumed frames synchronously. The sink also
        // consumes frames when muted or dropping a full queue.
        if (speed == 1) audioOutput?.batch(data, frames);
        return frames;
      }, exceptionalReturn: 0,
    );
    pollCb = NativeCallable<InputPollNative>.isolateLocal(() {});
    stateCb = NativeCallable<InputStateNative>.isolateLocal(
      (int port, int device, int index, int id) =>
          port < roms.length && device == 1 && index == 0 && id < 16 &&
                  (input.masks[port] & (1 << id)) != 0 ? 1 : 0,
      exceptionalReturn: 0,
    );

    library.lookupFunction<SetEnvironmentNative, SetEnvironmentDart>(
        'retro_set_environment')(envCb.nativeFunction);
    library.lookupFunction<SetVideoNative, SetVideoDart>(
        'retro_set_video_refresh')(videoCb.nativeFunction);
    library.lookupFunction<SetAudioSampleNative, SetAudioSampleDart>(
        'retro_set_audio_sample')(audioCb.nativeFunction);
    library.lookupFunction<SetAudioBatchNative, SetAudioBatchDart>(
        'retro_set_audio_sample_batch')(batchCb.nativeFunction);
    library.lookupFunction<SetInputPollNative, SetInputPollDart>(
        'retro_set_input_poll')(pollCb.nativeFunction);
    library.lookupFunction<SetInputStateNative, SetInputStateDart>(
        'retro_set_input_state')(stateCb.nativeFunction);

    final init = library.lookupFunction<LifecycleNative, LifecycleDart>('retro_init');
    deinit = library.lookupFunction<LifecycleNative, LifecycleDart>('retro_deinit');
    unload = library.lookupFunction<LifecycleNative, LifecycleDart>('retro_unload_game');
    final load = library.lookupFunction<LoadGameNative, LoadGameDart>('retro_load_game');
    final retroRun = library.lookupFunction<RetroRunNative, RetroRunDart>('retro_run');
    final setControllerPortDevice = library.lookupFunction<
        Void Function(Uint32, Uint32), void Function(int, int)>(
        'retro_set_controller_port_device');
    final av = library.lookupFunction<GetAvInfoNative, GetAvInfoDart>(
        'retro_get_system_av_info');

    phase = 'init';
    init();
    initialized = true;
    final gameInfo = arena<RetroGameInfo>(roms.length);
    for (var i = 0; i < roms.length; i++) {
      final content = cartridges[i];
      final nativeRom = arena<Uint8>(content.length);
      nativeRom.asTypedList(content.length).setAll(0, content);
      gameInfo[i].path = roms[i].absolute.path.toNativeUtf8(allocator: arena);
      gameInfo[i].data = nativeRom.cast<Void>();
      gameInfo[i].size = content.length;
      gameInfo[i].meta = nullptr;
    }
    phase = 'load';
    if (link != null) {
      final id = link.id;
      if (id == null) throw StateError('Subsistema gb_link_2p ausente.');
      final special = library.lookupFunction<
          Uint8 Function(Uint32, Pointer<RetroGameInfo>, Size),
          int Function(int, Pointer<RetroGameInfo>, int)>('retro_load_game_special');
      loaded = special(id, gameInfo, 2) != 0;
    } else {
      loaded = load(gameInfo) != 0;
    }
    if (!loaded) throw StateError('SameBoy recusou o carregamento da ROM.');
    for (var i = 0; i < roms.length; i++) {
      setControllerPortDevice(i, 1);
      final save = await CartridgeSave.attach(library, cartridges[i],
          linkPort: dual ? i : null);
      if (save != null) saves.add(save);
      if (!dual) cartridgeSave = save;
    }

    final avInfo = calloc<RetroSystemAvInfo>();
    phase = 'av_info';
    double fps;
    late final double sampleRate;
    try {
      av(avInfo);
      fps = avInfo.ref.timing.fps;
      sampleRate = avInfo.ref.timing.sampleRate;
      if (dual && (avInfo.ref.geometry.baseWidth != linkWidth ||
          avInfo.ref.geometry.baseHeight != linkHeight)) {
        throw StateError('Geometria Link Cable inesperada: ${avInfo.ref.geometry.baseWidth} × ${avInfo.ref.geometry.baseHeight}');
      }
    } finally {
      calloc.free(avInfo);
    }
    if (fps < 30 || fps > 120) fps = 59.73;
    final periodUs = (1000000 / fps).round();
    final commandsV2 = !dual && Platform.environment[sameBoyCommandEnvironment] == '1';
    int nextFrameUs = 0;
    final clock = Stopwatch()..start();
    int? stateCommand;
    SameBoyStates? states;
    var cartridgeProtected = false;
    if (launchVolume != null || commandsV2) {
      volumeCommands = stdin.listen((bytes) {
        if (commandsV2) {
          for (final byte in bytes) {
            if (byte >= speedNormal && byte <= speedQuad) {
              final requested = byte - speedNormal + 1;
              if (requested != speed) {
                speed = requested;
                audioOutput?.setVolume(speed > 1 ? 0 : volume);
                nextFrameUs = clock.elapsedMicroseconds;
              }
            }
            if (isStateCommand(byte)) stateCommand ??= byte;
          }
        }
        final value = latestVolume(bytes);
        if (value != null && volume != value) {
          volume = value;
          if (speed == 1) audioOutput?.setVolume(volume);
        }
      }, onError: (Object error) => stderr.writeln('Canal de volume: $error'));
    }
    audioOutput = SameBoyAudioOutput.open(sampleRate);
    audioOutput?.setVolume(volume);
    stdout.writeln('SameBoy ativo. Emulacao: ${fps.toStringAsFixed(2)} fps');

    stdout.writeln('Audio: target=${offerTarget ? 48000 : "off"} '
        'queries=$targetQueries phase=$queryPhase rate=$sampleRate Hz');
    var nextSaveUs = const Duration(seconds: 5).inMicroseconds;
    phase = 'run';
    while (running) {
      final now = clock.elapsedMicroseconds;
      if (now < nextFrameUs) {
        final remaining = nextFrameUs - now;
        await Future<void>.delayed(Duration(
            microseconds: remaining > 2000 ? 1000 : remaining));
        continue;
      }
      frameNumber++;
      rawFrame = null;
      retroRun();
      final command = stateCommand;
      if (command != null) {
        stateCommand = null;
        final reply = <String, Object?>{'command': command};
        try {
          final local = Platform.environment['LOCALAPPDATA'];
          if (local == null || local.isEmpty) throw StateError('LOCALAPPDATA indisponível.');
          final store = states ??= SameBoyStates(library, romIdentity, core, Directory('$local/BeastEmu/states'));
          if (command == listStateSlots) {
            reply['slots'] = await store.list();
          } else {
            await store.execute(command, () async {
              await cartridgeSave?.protectBeforeStateLoad();
              cartridgeProtected = true;
            });
          }
        } on EmptyQuickSlot {
          reply['empty'] = true;
        } catch (error) {
          reply['error'] = error.toString();
        }
        reply['protected'] = cartridgeProtected;
        stdout.writeln('$stateReplyPrefix${jsonEncode(reply)}');
      }
      if (now >= nextSaveUs) {
        nextSaveUs = now + const Duration(seconds: 5).inMicroseconds;
        for (final save in saves) {
          unawaited(save.checkpoint());
        }
      }
      if (frameNumber == 120) {
        stdout.writeln('Audio/120 retro_run: $audioFrames stereo frames, '
            '$batches batches, $singles single samples');
      }
      if (frameNumber.isEven && rawFrame != null) {
        final rgba = LibretroFrameConverter.toRgba8888(
          pixels: rawFrame!, width: rawWidth, height: rawHeight,
          pitch: rawPitch,
          format: LibretroPixelFormat.fromLibretroValue(rawFormat),
        );
        // A stalled renderer may skip images. Never accumulate old frames
        // or block emulation, cartridge checkpoints or command handling.
        videoPending = true;
        socket.add(rgba);
        unawaited(socket.flush().then<void>((_) { videoPending = false; },
            onError: (Object _) { running = false; }));
      }
      final interval = periodUs ~/ speed;
      nextFrameUs += interval;
      if (clock.elapsedMicroseconds - nextFrameUs > interval * 3) {
        nextFrameUs = clock.elapsedMicroseconds + interval;
      }
      // Cedemos a thread ao loop de eventos para receber teclas e fechamento.
      await Future<void>.delayed(Duration.zero);
    }
  } catch (error, trace) {
    stderr.writeln('Erro SameBoy em tempo real: $error');
    stderr.writeln(trace);
    exitCode = 1;
  } finally {
    // Core e callbacks permanecem validos ate retro_unload/retro_deinit.
    try {
      try {
        await Future.wait(saves.map((save) => save.close(reportFailure: dual)));
      } catch (error) {
        stderr.writeln('Falha na gravação final dos cartuchos: $error');
        exitCode = 1;
      } finally {
        if (loaded) unload?.call();
      }
      if (initialized) deinit?.call();
    } finally {
      arena.releaseAll();
      stateCb?.close();
      pollCb?.close();
      batchCb?.close();
      unawaited(volumeCommands?.cancel());
      audioOutput?.close();
      audioOutput = null;
      audioCb?.close();
      videoCb?.close();
      envCb?.close();
      socket?.destroy();
    }
  }
  // Windows can keep a blocking stdin read alive even after cancel(), if the
  // parent closes TCP but retains the pipe. All cartridge I/O, native cleanup
  // and socket teardown have completed before terminating this CLI process.
  if (volumeCommands != null) {
    try {
      await stdout.flush();
      await stderr.flush();
    } finally {
      exit(exitCode);
    }
  }
}
