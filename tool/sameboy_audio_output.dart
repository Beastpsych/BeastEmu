import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// One PCM output per helper process. The native queue copies every input
/// before returning, including the scratch pair used by the single callback.
class SameBoyAudioOutput {
  SameBoyAudioOutput._(DynamicLibrary library)
    : _write = library
          .lookupFunction<
            Int32 Function(Pointer<Int16>, Size),
            int Function(Pointer<Int16>, int)
          >('audio_write'),
      _setVolume = library
          .lookupFunction<Int32 Function(Uint32), int Function(int)>(
            'audio_set_volume',
          ),
      _close = library.lookupFunction<Void Function(), void Function()>(
        'audio_close',
      );

  final int Function(Pointer<Int16>, int) _write;
  final int Function(int) _setVolume;
  final void Function() _close;
  final Pointer<Int16> _pair = calloc<Int16>(2);
  int _error = 0;

  static SameBoyAudioOutput? open(
    double sampleRate, {
    bool useCoreRate = false,
  }) {
    if (!sampleRate.isFinite ||
        sampleRate < 8000 ||
        sampleRate > 192000 ||
        sampleRate != sampleRate.roundToDouble() ||
        (!useCoreRate && sampleRate != 48000)) {
      stderr.writeln('Audio desativado: taxa do nucleo $sampleRate Hz.');
      return null;
    }
    try {
      final path = Platform.environment['BEASTEMU_AUDIO_DLL'];
      if (path == null) throw StateError('Caminho da DLL de audio ausente.');
      final library = DynamicLibrary.open(path);
      final open = library.lookupFunction<Int32 Function(), int Function()>(
        'audio_open',
      );
      final output = SameBoyAudioOutput._(library);
      final hr = useCoreRate
          ? library.lookupFunction<Int32 Function(Uint32), int Function(int)>(
              'audio_open_at_rate',
            )(sampleRate.toInt())
          : open();
      if (hr < 0) {
        output.close();
        throw StateError(
          'XAudio2 HRESULT 0x${hr.toUnsigned(32).toRadixString(16)}',
        );
      }
      stdout.writeln('XAudio2 ativo: PCM estereo, ${sampleRate.toInt()} Hz.');
      return output;
    } catch (error) {
      stderr.writeln('Audio desativado: $error');
      return null;
    }
  }

  void batch(Pointer<Int16> samples, int frames) {
    if (_error >= 0 && frames > 0 && samples != nullptr) {
      try {
        _error = _write(samples, frames);
      } catch (_) {
        // Keep the core consuming batches if FFI output fails.
        _error = -1;
      }
    }
  }

  void setVolume(int percent) {
    if (_error >= 0) _error = _setVolume(percent.clamp(0, 100));
  }

  void sample(int left, int right) {
    _pair[0] = left;
    _pair[1] = right;
    batch(_pair, 1);
  }

  void close() {
    if (_error < 0) {
      stderr.writeln('XAudio2 interrompido: HRESULT $_error');
    }
    _close();
    calloc.free(_pair);
  }
}
