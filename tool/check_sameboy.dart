
import 'dart:ffi';
import 'dart:io';

typedef RetroApiVersionNative = Uint32 Function();
typedef RetroApiVersionDart = int Function();

void main() {
  stdout.writeln('===== BEASTEMU =====');
  stdout.writeln('Teste de integracao SameBoy');

  if (!Platform.isWindows) {
    stderr.writeln('Este teste foi preparado para Windows.');
    exitCode = 1;
    return;
  }

  final coreFile = File(
    'cores/windows/sameboy_libretro.dll',
  );

  if (!coreFile.existsSync()) {
    stderr.writeln('Nucleo SameBoy nao encontrado.');
    exitCode = 1;
    return;
  }

  try {
    final library = DynamicLibrary.open(
      coreFile.absolute.path,
    );

    stdout.writeln('Biblioteca carregada com sucesso!');

    final getApiVersion = library.lookupFunction<
        RetroApiVersionNative,
        RetroApiVersionDart>(
      'retro_api_version',
    );

    final apiVersion = getApiVersion();

    stdout.writeln('Versao da API Libretro: $apiVersion');

    if (apiVersion == 1) {
      stdout.writeln('SameBoy reconhecido pelo BeastEmu!');
    } else {
      stderr.writeln('Versao da API inesperada.');
      exitCode = 1;
    }
  } catch (error) {
    stderr.writeln('Falha ao carregar nucleo: $error');
    exitCode = 1;
  }
}
