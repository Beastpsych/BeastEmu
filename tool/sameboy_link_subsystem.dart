import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class _Subsystem extends Struct {
  external Pointer<Utf8> description;
  external Pointer<Utf8> ident;
  external Pointer<Void> roms;
  @Uint32()
  external int count;
  @Uint32()
  external int id;
}

final class _Variable extends Struct {
  external Pointer<Utf8> key;
  external Pointer<Utf8> value;
}

class LinkSubsystem {
  LinkSubsystem(Arena arena)
    : _values = {
        for (final entry in const {
          'sameboy_link': 'enabled',
          'sameboy_screen_layout': 'left-right',
          'sameboy_audio_output': 'Game Boy #1',
        }.entries)
          entry.key: entry.value.toNativeUtf8(allocator: arena),
      };
  final Map<String, Pointer<Utf8>> _values;
  int? id;

  int environment(int command, Pointer<Void> data) {
    if (data == nullptr) return 0;
    if (command == 34) {
      // SET_SUBSYSTEM_INFO, terminated by a null description
      final list = data.cast<_Subsystem>();
      for (var i = 0; i < 32 && list[i].description != nullptr; i++) {
        final item = list[i];
        if (item.ident != nullptr &&
            item.ident.toDartString() == 'gb_link_2p' &&
            item.count == 2 &&
            item.roms != nullptr) {
          id = item.id;
          return 1;
        }
      }
    }
    if (command == 15) {
      // GET_VARIABLE
      final variable = data.cast<_Variable>().ref;
      if (variable.key == nullptr) return 0;
      final value = _values[variable.key.toDartString()];
      variable.value = value ?? nullptr;
      return value == null ? 0 : 1;
    }
    return 0;
  }
}
