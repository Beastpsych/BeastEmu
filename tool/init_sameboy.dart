
import 'dart:ffi';
import 'dart:io';

// Callback de ambiente usado pela API Libretro.
typedef RetroEnvironmentNative =
    Uint8 Function(Uint32, Pointer<Void>);

typedef SetEnvironmentNative = Void Function(
  Pointer<NativeFunction<RetroEnvironmentNative>>,
);

typedef SetEnvironmentDart = void Function(
  Pointer<NativeFunction<RetroEnvironmentNative>>,
);

// Funcoes de inicializacao e encerramento.
typedef RetroLifecycleNative = Void Function();
typedef RetroLifecycleDart = void Function();

void main() {
  stdout.writeln('===== BEASTEMU =====');
  stdout.writeln('Teste de inicializacao do SameBoy');

  if (!Platform.isWindows) {
    stderr.writeln('Teste disponivel apenas no Windows.');
    exitCode = 1;
    return;
  }

  final coreFile = File(
    'cores/windows/sameboy_libretro.dll',
  );

  if (!coreFile.existsSync()) {
    stderr.writeln('DLL do SameBoy nao encontrada.');
    exitCode = 1;
    return;
  }

  final requests = <int>{};
  NativeCallable<RetroEnvironmentNative>? callback;
  RetroLifecycleDart? deinit;
  var initialized = false;

  try {
    final library = DynamicLibrary.open(
      coreFile.absolute.path,
    );

    final setEnvironment = library.lookupFunction<
        SetEnvironmentNative,
        SetEnvironmentDart>(
      'retro_set_environment',
    );

    final init = library.lookupFunction<
        RetroLifecycleNative,
        RetroLifecycleDart>(
      'retro_init',
    );

    deinit = library.lookupFunction<
        RetroLifecycleNative,
        RetroLifecycleDart>(
      'retro_deinit',
    );

    // Callback temporario para o teste.
    // Informa que recursos opcionais ainda nao
    // estao implementados neste frontend.
    callback = NativeCallable<
        RetroEnvironmentNative>.isolateLocal(
      (int command, Pointer<Void> data) {
        requests.add(command);
        return 0;
      },
      exceptionalReturn: 0,
    );

    setEnvironment(callback.nativeFunction);
    stdout.writeln('Callback de ambiente registrado.');

    init();
    initialized = true;

    stdout.writeln('SameBoy inicializado!');
    stdout.writeln(
      'Solicitacoes de ambiente: ${requests.toList()}',
    );
  } catch (error) {
    stderr.writeln('Erro de integracao: $error');
    exitCode = 1;
  } finally {
    try {
      if (initialized) {
        deinit?.call();
        stdout.writeln('SameBoy encerrado.');
      }
    } finally {
      callback?.close();
    }
  }

  if (initialized) {
    stdout.writeln('Teste concluido!');
  }
}
