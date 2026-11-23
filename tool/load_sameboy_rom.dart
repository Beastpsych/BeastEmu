import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// BeastEmu - Etapa 04.6: teste isolado de carregamento de ROM.
// Este script NAO executa quadros, audio nem altera a interface Flutter.
// Ele deve ser usado apenas com ROMs que voce tenha permissao para utilizar.

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

Future<void> main(List<String> args) async {
  if (!Platform.isWindows) {
    stderr.writeln('Este teste foi preparado apenas para Windows.');
    exitCode = 1;
    return;
  }
  if (args.length != 1) {
    stderr.writeln('Uso: dart run tool/load_sameboy_rom.dart "caminho\\jogo.gb"');
    exitCode = 1;
    return;
  }

  final core = File('cores/windows/sameboy_libretro.dll');
  final rom = File(args.single);
  if (!core.existsSync() || !rom.existsSync()) {
    stderr.writeln('Nucleo ou arquivo ROM nao encontrado.');
    exitCode = 1;
    return;
  }

  // Nao abrir diretórios, nem arquivos inesperados.
  final extension = rom.path.toLowerCase().split('.').last;
  if (extension != 'gb' && extension != 'gbc') {
    stderr.writeln('Use um arquivo .gb ou .gbc extraido.');
    exitCode = 1;
    return;
  }

  final bytes = await rom.readAsBytes();
  if (bytes.length < 0x150) {
    stderr.writeln('Arquivo pequeno demais para uma ROM GB/GBC.');
    exitCode = 1;
    return;
  }

  NativeCallable<EnvironmentNative>? environmentCallback;
  NativeCallable<VideoNative>? videoCallback;
  NativeCallable<AudioSampleNative>? audioCallback;
  NativeCallable<AudioBatchNative>? audioBatchCallback;
  NativeCallable<InputPollNative>? inputPollCallback;
  NativeCallable<InputStateNative>? inputStateCallback;

  Pointer<Uint8>? nativeRom;
  Pointer<Utf8>? nativePath;
  Pointer<RetroGameInfo>? gameInfo;
  LifecycleDart? deinit;
  LifecycleDart? unload;
  bool initialized = false;
  bool loaded = false;

  try {
    final library = DynamicLibrary.open(core.absolute.path);

    // Callback de ambiente: implementa somente pedidos que sabemos atender.
    // false = recurso opcional indisponivel. Nao afirmar suporte falso.
    environmentCallback = NativeCallable<EnvironmentNative>.isolateLocal(
      (int command, Pointer<Void> data) {
        switch (command) {
          case 3: // GET_CAN_DUPE
            if (data.address == 0) return 0;
            data.cast<Uint8>().value = 0; // Sem frame duplication neste teste.
            return 1;
          case 10: // SET_PIXEL_FORMAT
            if (data.address == 0) return 0;
            final format = data.cast<Int32>().value;
            // Suportamos receber ambos os formatos comuns de 16/32 bits.
            return (format == 0 || format == 1 || format == 2) ? 1 : 0;
          case 17: // GET_VARIABLE_UPDATE
            if (data.address == 0) return 0;
            data.cast<Uint8>().value = 0;
            return 1;
          case 52: // GET_CORE_OPTIONS_VERSION
            if (data.address == 0) return 0;
            data.cast<Uint32>().value = 0; // API legada das opcoes.
            return 1;
          default:
            return 0;
        }
      },
      exceptionalReturn: 0,
    );

    // Callbacks obrigatorios; ainda nao executamos frames.
    videoCallback = NativeCallable<VideoNative>.isolateLocal(
      (Pointer<Void> data, int width, int height, int pitch) {},
    );
    audioCallback = NativeCallable<AudioSampleNative>.isolateLocal(
      (int left, int right) {},
    );
    audioBatchCallback = NativeCallable<AudioBatchNative>.isolateLocal(
      (Pointer<Int16> data, int frames) => frames,
      exceptionalReturn: 0,
    );
    inputPollCallback = NativeCallable<InputPollNative>.isolateLocal(() {});
    inputStateCallback = NativeCallable<InputStateNative>.isolateLocal(
      (int port, int device, int index, int id) => 0,
      exceptionalReturn: 0,
    );

    library.lookupFunction<SetEnvironmentNative, SetEnvironmentDart>(
      'retro_set_environment',
    )(environmentCallback.nativeFunction);
    library.lookupFunction<SetVideoNative, SetVideoDart>(
      'retro_set_video_refresh',
    )(videoCallback.nativeFunction);
    library.lookupFunction<SetAudioSampleNative, SetAudioSampleDart>(
      'retro_set_audio_sample',
    )(audioCallback.nativeFunction);
    library.lookupFunction<SetAudioBatchNative, SetAudioBatchDart>(
      'retro_set_audio_sample_batch',
    )(audioBatchCallback.nativeFunction);
    library.lookupFunction<SetInputPollNative, SetInputPollDart>(
      'retro_set_input_poll',
    )(inputPollCallback.nativeFunction);
    library.lookupFunction<SetInputStateNative, SetInputStateDart>(
      'retro_set_input_state',
    )(inputStateCallback.nativeFunction);

    final init = library.lookupFunction<LifecycleNative, LifecycleDart>(
      'retro_init',
    );
    deinit = library.lookupFunction<LifecycleNative, LifecycleDart>(
      'retro_deinit',
    );
    unload = library.lookupFunction<LifecycleNative, LifecycleDart>(
      'retro_unload_game',
    );
    final load = library.lookupFunction<LoadGameNative, LoadGameDart>(
      'retro_load_game',
    );
    final getAvInfo = library.lookupFunction<GetAvInfoNative, GetAvInfoDart>(
      'retro_get_system_av_info',
    );

    stdout.writeln('===== BEASTEMU | TESTE DE ROM =====');
    init();
    initialized = true;
    stdout.writeln('SameBoy inicializado.');

    nativeRom = calloc<Uint8>(bytes.length);
    nativeRom.asTypedList(bytes.length).setAll(0, bytes);
    nativePath = rom.absolute.path.toNativeUtf8();
    gameInfo = calloc<RetroGameInfo>();
    gameInfo.ref.path = nativePath;
    gameInfo.ref.data = nativeRom.cast<Void>();
    gameInfo.ref.size = bytes.length;
    gameInfo.ref.meta = nullptr;

    loaded = load(gameInfo) != 0;
    if (!loaded) {
      stderr.writeln('SameBoy recusou o carregamento da ROM.');
      exitCode = 1;
      return;
    }
    stdout.writeln('ROM carregada na memoria do SameBoy!');

    final avInfo = calloc<RetroSystemAvInfo>();
    try {
      getAvInfo(avInfo);
      stdout.writeln('Resolucao base: '
          '${avInfo.ref.geometry.baseWidth}x${avInfo.ref.geometry.baseHeight}');
      stdout.writeln('FPS informado: '
          '${avInfo.ref.timing.fps.toStringAsFixed(2)}');
      stdout.writeln('Frequencia de audio: '
          '${avInfo.ref.timing.sampleRate.toStringAsFixed(0)} Hz');
    } finally {
      calloc.free(avInfo);
    }
    stdout.writeln('Teste concluido sem executar frames.');
  } catch (error) {
    stderr.writeln('Erro durante o teste nativo: $error');
    exitCode = 1;
  } finally {
    // O core deve liberar quaisquer referencias antes da liberacao da ROM.
    try {
      if (loaded) unload?.call();
      if (initialized) deinit?.call();
    } finally {
      if (gameInfo != null) calloc.free(gameInfo);
      if (nativePath != null) calloc.free(nativePath);
      if (nativeRom != null) calloc.free(nativeRom);
      inputStateCallback?.close();
      inputPollCallback?.close();
      audioBatchCallback?.close();
      audioCallback?.close();
      videoCallback?.close();
      environmentCallback?.close();
    }
  }
}
