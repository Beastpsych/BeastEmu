import 'dart:ffi';

import 'package:ffi/ffi.dart';

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
typedef InputStateNative = Int16 Function(Uint32, Uint32, Uint32, Uint32);

typedef SetEnvironmentNative = Void Function(
  Pointer<NativeFunction<EnvironmentNative>>,
);
typedef SetVideoNative = Void Function(Pointer<NativeFunction<VideoNative>>);
typedef SetAudioSampleNative = Void Function(
  Pointer<NativeFunction<AudioSampleNative>>,
);
typedef SetAudioBatchNative = Void Function(
  Pointer<NativeFunction<AudioBatchNative>>,
);
typedef SetInputPollNative = Void Function(
  Pointer<NativeFunction<InputPollNative>>,
);
typedef SetInputStateNative = Void Function(
  Pointer<NativeFunction<InputStateNative>>,
);

typedef SetEnvironmentDart = void Function(
  Pointer<NativeFunction<EnvironmentNative>>,
);
typedef SetVideoDart = void Function(Pointer<NativeFunction<VideoNative>>);
typedef SetAudioSampleDart = void Function(
  Pointer<NativeFunction<AudioSampleNative>>,
);
typedef SetAudioBatchDart = void Function(
  Pointer<NativeFunction<AudioBatchNative>>,
);
typedef SetInputPollDart = void Function(
  Pointer<NativeFunction<InputPollNative>>,
);
typedef SetInputStateDart = void Function(
  Pointer<NativeFunction<InputStateNative>>,
);

typedef LifecycleNative = Void Function();
typedef LifecycleDart = void Function();
typedef LoadGameNative = Uint8 Function(Pointer<RetroGameInfo>);
typedef LoadGameDart = int Function(Pointer<RetroGameInfo>);
typedef GetAvInfoNative = Void Function(Pointer<RetroSystemAvInfo>);
typedef GetAvInfoDart = void Function(Pointer<RetroSystemAvInfo>);

// retro_run executa um quadro de emulacao a cada chamada.
typedef RetroRunNative = Void Function();
typedef RetroRunDart = void Function();
