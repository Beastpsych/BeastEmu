import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:beastemu/services/gba_cartridge.dart';
import 'package:beastemu/services/libretro_frame_converter.dart';
import 'package:beastemu/services/sameboy_commands.dart';
import 'package:beastemu/services/sameboy_link_protocol.dart';
import 'package:beastemu/services/sameboy_volume_control.dart';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';

import 'inspect_sameboy.dart'
    show RetroSystemInfo, GetSystemInfoNative, GetSystemInfoDart;
import 'libretro_abi.dart';
import 'sameboy_audio_output.dart';
import 'mgba_save.dart';
import 'mgba_states.dart';

Future<void> main(List<String> args) async {
  final arena = Arena();
  final cleanup = <void Function()>[];
  MgbaSave? save;
  Socket? socket;
  StreamSubscription<List<int>>? commands;
  SameBoyAudioOutput? audio;
  try {
    if (!Platform.isWindows ||
        args.length != 2 ||
        coreForPath(args[0]) != CartridgeCore.mgba) {
      throw const FormatException('Uso: mgba-live <rom.gba> <porta>');
    }
    final file = File(args[0]);
    if (await file.length() > 32 * 1024 * 1024) {
      throw const FormatException('Cartucho acima de 32 MiB.');
    }
    final rom = await file.readAsBytes();
    gbaTitle(rom);
    final romHash = sha256.convert(rom);
    final romId = romHash.toString();
    final expected = Platform.environment[expectedRomEnvironment];
    if (expected != null && expected.isNotEmpty && romId != expected) {
      throw const FormatException(
        'O conteúdo da ROM GBA diverge da biblioteca.',
      );
    }
    final core = File('cores/windows/mgba_libretro.dll');
    if (!await core.exists()) throw StateError('DLL mGBA ausente.');
    if ((await sha256.bind(core.openRead()).first).toString() != mgbaCoreHash) {
      throw StateError('DLL mGBA incompatível com esta revisão.');
    }
    final lib = DynamicLibrary.open(core.absolute.path);
    final api = lib.lookupFunction<Uint32 Function(), int Function()>(
      'retro_api_version',
    );
    final info = arena<RetroSystemInfo>();
    lib.lookupFunction<GetSystemInfoNative, GetSystemInfoDart>(
      'retro_get_system_info',
    )(info);
    if (api() != 1 ||
        info.ref.libraryName.toDartString() != 'mGBA' ||
        info.ref.needFullpath != 0 ||
        !info.ref.validExtensions.toDartString().split('|').contains('gba')) {
      throw StateError('ABI ou formato de conteúdo incompatível.');
    }
    final input = JoypadPackets(dual: false);
    MgbaStates? states;
    int? stateCommand;
    var cartridgeProtected = false;
    var running = true;
    var pending = false;
    var width = 0, height = 0;
    var format = LibretroPixelFormat.rgb1555;
    var frame = 0, samples = 0;
    String? videoError;
    Uint8List? rgba;

    final environment = NativeCallable<EnvironmentNative>.isolateLocal((
      int cmd,
      Pointer<Void> data,
    ) {
      if (data == nullptr) return 0;
      switch (cmd) {
        case 3: // GET_CAN_DUPE
        case 17: // GET_VARIABLE_UPDATE
          data.cast<Uint8>().value = 0;
          return 1;
        case 10: // SET_PIXEL_FORMAT
          final value = data.cast<Int32>().value;
          if (value < 0 || value > 2) return 0;
          format = LibretroPixelFormat.fromLibretroValue(value);
          return 1;
        default:
          return 0;
      }
    }, exceptionalReturn: 0);
    cleanup.add(environment.close);
    final video = NativeCallable<VideoNative>.isolateLocal((
      Pointer<Void> data,
      int w,
      int h,
      int pitch,
    ) {
      if (data == nullptr || pending || frame.isOdd) return;
      if (w != width ||
          h != height ||
          pitch < w * format.bytesPerPixel ||
          pitch > 8192) {
        videoError = 'O núcleo mudou a geometria ou o formato do vídeo.';
        return;
      }
      rgba = LibretroFrameConverter.toRgba8888(
        pixels: data.cast<Uint8>().asTypedList(
          (h - 1) * pitch + w * format.bytesPerPixel,
        ),
        width: w,
        height: h,
        pitch: pitch,
        format: format,
      );
    });
    cleanup.add(video.close);
    final batch = NativeCallable<AudioBatchNative>.isolateLocal((
      Pointer<Int16> pcm,
      int frames,
    ) {
      samples += frames;
      audio?.batch(pcm, frames);
      return frames;
    }, exceptionalReturn: 0);
    cleanup.add(batch.close);
    final sample = NativeCallable<AudioSampleNative>.isolateLocal((
      int l,
      int r,
    ) {
      samples++;
      audio?.sample(l, r);
    });
    cleanup.add(sample.close);
    final poll = NativeCallable<InputPollNative>.isolateLocal(() {});
    cleanup.add(poll.close);
    final state = NativeCallable<InputStateNative>.isolateLocal(
      (int port, int device, int index, int id) =>
          port == 0 && device == 1 && index == 0 && id < 16
          ? (input.masks[0] >> id) & 1
          : 0,
      exceptionalReturn: 0,
    );
    cleanup.add(state.close);

    lib.lookupFunction<SetEnvironmentNative, SetEnvironmentDart>(
      'retro_set_environment',
    )(environment.nativeFunction);
    lib.lookupFunction<SetVideoNative, SetVideoDart>('retro_set_video_refresh')(
      video.nativeFunction,
    );
    lib.lookupFunction<SetAudioSampleNative, SetAudioSampleDart>(
      'retro_set_audio_sample',
    )(sample.nativeFunction);
    lib.lookupFunction<SetAudioBatchNative, SetAudioBatchDart>(
      'retro_set_audio_sample_batch',
    )(batch.nativeFunction);
    lib.lookupFunction<SetInputPollNative, SetInputPollDart>(
      'retro_set_input_poll',
    )(poll.nativeFunction);
    lib.lookupFunction<SetInputStateNative, SetInputStateDart>(
      'retro_set_input_state',
    )(state.nativeFunction);

    final deinit = lib.lookupFunction<LifecycleNative, LifecycleDart>(
      'retro_deinit',
    );
    final unload = lib.lookupFunction<LifecycleNative, LifecycleDart>(
      'retro_unload_game',
    );
    lib.lookupFunction<LifecycleNative, LifecycleDart>('retro_init')();
    cleanup.add(deinit);
    final game = arena<RetroGameInfo>();
    final content = arena<Uint8>(rom.length)
      ..asTypedList(rom.length).setAll(0, rom);
    game.ref
      ..path = file.absolute.path.toNativeUtf8(allocator: arena)
      ..data = content.cast()
      ..size = rom.length;
    if (lib.lookupFunction<LoadGameNative, LoadGameDart>('retro_load_game')(
          game,
        ) ==
        0) {
      throw const FormatException('mGBA recusou a ROM.');
    }
    cleanup.add(unload);
    save = await MgbaSave.attach(
      lib,
      romId,
      (status) => stdout.writeln('GBA_SAVE $status'),
    );
    lib.lookupFunction<Void Function(Uint32, Uint32), void Function(int, int)>(
      'retro_set_controller_port_device',
    )(0, 1);
    final av = arena<RetroSystemAvInfo>();
    lib.lookupFunction<GetAvInfoNative, GetAvInfoDart>(
      'retro_get_system_av_info',
    )(av);
    width = av.ref.geometry.baseWidth;
    height = av.ref.geometry.baseHeight;
    final fps = av.ref.timing.fps, rate = av.ref.timing.sampleRate;
    if (width < 1 ||
        height < 1 ||
        width > 512 ||
        height > 512 ||
        !fps.isFinite ||
        fps < 1 ||
        fps > 240) {
      throw StateError('Geometria ou FPS inválidos.');
    }
    final memorySize = lib
        .lookupFunction<Size Function(Uint32), int Function(int)>(
          'retro_get_memory_size',
        );
    stdout.writeln(
      'mGBA ${info.ref.libraryVersion.toDartString()} · ${width}x$height · $fps fps · $rate Hz · ${format.name} · SAVE_RAM=${memorySize(0)} RTC=${memorySize(1)}',
    );
    final peer = socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      int.parse(args[1]),
      timeout: const Duration(seconds: 5),
    );
    peer.setOption(SocketOption.tcpNoDelay, true);
    peer.done.then<void>(
      (_) => running = false,
      onError: (Object _) => running = false,
    );
    peer.listen(
      input.add,
      onDone: () => running = false,
      onError: (Object _) => running = false,
    );
    final header = ByteData(4)
      ..setUint16(0, width, Endian.little)
      ..setUint16(2, height, Endian.little);
    peer.add(header.buffer.asUint8List());
    audio = SameBoyAudioOutput.open(rate, useCoreRate: true);
    audio?.setVolume(
      int.tryParse(Platform.environment[sameBoyVolumeEnvironment] ?? '') ?? 100,
    );
    commands = stdin.listen(
      (bytes) {
        for (final byte in bytes) {
          if (isStateCommand(byte)) stateCommand ??= byte;
        }
        final volume = latestVolume(bytes);
        if (volume != null) audio?.setVolume(volume);
      },
      onDone: () => running = false,
      onError: (Object _) => running = false,
    );
    final run = lib.lookupFunction<RetroRunNative, RetroRunDart>('retro_run');
    final interval = (1000000 / fps).round();
    final clock = Stopwatch()..start();
    var deadline = 0;
    while (running) {
      rgba = null;
      run();
      if (videoError != null) throw StateError(videoError!);
      final command = stateCommand;
      if (command != null) {
        stateCommand = null;
        final reply = <String, Object?>{'command': command};
        try {
          final local = Platform.environment['LOCALAPPDATA'];
          if (local == null || local.isEmpty) {
            throw StateError('LOCALAPPDATA indisponível.');
          }
          final store = states ??= MgbaStates(
            lib,
            romHash,
            core,
            info.ref.libraryVersion.toDartString(),
            Directory('$local/BeastEmu/states/mgba'),
          );
          if (command == listStateSlots) {
            reply['slots'] = await store.list();
          } else {
            await store.execute(command, () async {
              await save!.protectBeforeStateLoad();
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
      if (rgba case final pixels?) {
        pending = true;
        peer.add(pixels);
        unawaited(
          peer.flush().then<void>(
            (_) => pending = false,
            onError: (Object _) => running = false,
          ),
        );
      }
      frame++;
      if (frame == 1 || frame % 300 == 0) save.tick();
      deadline += interval;
      if (clock.elapsedMicroseconds - deadline > interval * 3) {
        deadline = clock.elapsedMicroseconds;
      }
      await Future<void>.delayed(
        Duration(microseconds: deadline - clock.elapsedMicroseconds),
      );
    }
    final finishing = save;
    save = null;
    await finishing.close(flush: true);
    stdout.writeln(
      'mGBA encerrado · $frame quadros · $samples amostras estéreo.',
    );
  } catch (error) {
    stderr.writeln('Falha na sessão mGBA: $error');
    exitCode = 1;
  } finally {
    try {
      await save?.close(flush: false);
    } catch (error) {
      stderr.writeln(error);
      exitCode = 1;
    }
    for (final close in cleanup.reversed) {
      close();
    }
    audio?.close();
    arena.releaseAll();
    socket?.destroy();
    unawaited(commands?.cancel());
  }
  if (commands != null) {
    await stdout.flush();
    await stderr.flush();
    exit(exitCode);
  }
}
