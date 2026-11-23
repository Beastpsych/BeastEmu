
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Estrutura definida pela API Libretro.
final class RetroSystemInfo extends Struct {
  external Pointer<Utf8> libraryName;
  external Pointer<Utf8> libraryVersion;
  external Pointer<Utf8> validExtensions;

  @Uint8()
  external int needFullpath;

  @Uint8()
  external int blockExtract;
}

typedef GetSystemInfoNative = Void Function(
  Pointer<RetroSystemInfo>,
);

typedef GetSystemInfoDart = void Function(
  Pointer<RetroSystemInfo>,
);

void main() {
  final coreFile = File(
    'cores/windows/sameboy_libretro.dll',
  );

  if (!coreFile.existsSync()) {
    stderr.writeln('SameBoy nao encontrado.');
    exitCode = 1;
    return;
  }

  try {
    final library = DynamicLibrary.open(
      coreFile.absolute.path,
    );

    final getInfo = library.lookupFunction<
        GetSystemInfoNative,
        GetSystemInfoDart>(
      'retro_get_system_info',
    );

    final info = calloc<RetroSystemInfo>();

    try {
      getInfo(info);

      stdout.writeln('===== BEASTEMU =====');
      stdout.writeln('Informacoes do SameBoy');
      stdout.writeln('');

      stdout.writeln(
        'Nome: ${info.ref.libraryName.toDartString()}',
      );

      stdout.writeln(
        'Versao: ${info.ref.libraryVersion.toDartString()}',
      );

      stdout.writeln(
        'Extensoes: ${info.ref.validExtensions.toDartString()}',
      );

      stdout.writeln(
        'Exige caminho completo: ${info.ref.needFullpath != 0}',
      );

      stdout.writeln(
        'Bloqueia extracao: ${info.ref.blockExtract != 0}',
      );

      stdout.writeln('====================');
    } finally {
      calloc.free(info);
    }
  } catch (error) {
    stderr.writeln('Erro: $error');
    exitCode = 1;
  }
}
