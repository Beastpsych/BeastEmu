import 'dart:io';
import 'package:beastemu/services/game_boy_header.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln('Informe o caminho de uma ROM GB/GBC.');
    return;
  }

  try {
    final game = await GameBoyHeaderReader.read(args[0]);

    stdout.writeln('');
    stdout.writeln('===== BEASTEMU =====');
    stdout.writeln('Titulo: ${game.title}');
    stdout.writeln('Console: ${game.console}');
    stdout.writeln('====================');
  } catch (error) {
    stderr.writeln('Erro ao analisar ROM: $error');
    exitCode = 1;
  }
}
