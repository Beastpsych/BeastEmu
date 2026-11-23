import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

// The first 16 bits match XINPUT_GAMEPAD.wButtons. The extra bits represent
// triggers and left stick directions after applying their thresholds.
enum PadControl {
  up(0x0001, 'D-pad ↑'),
  down(0x0002, 'D-pad ↓'),
  left(0x0004, 'D-pad ←'),
  right(0x0008, 'D-pad →'),
  start(0x0010, 'Menu / Start'),
  back(0x0020, 'View / Back'),
  ls(0x0040, 'LS'),
  rs(0x0080, 'RS'),
  lb(0x0100, 'LB'),
  rb(0x0200, 'RB'),
  a(0x1000, 'A'),
  b(0x2000, 'B'),
  x(0x4000, 'X'),
  y(0x8000, 'Y'),
  lt(1 << 16, 'LT'),
  rt(1 << 17, 'RT'),
  stickUp(1 << 18, 'Analógico ↑'),
  stickDown(1 << 19, 'Analógico ↓'),
  stickLeft(1 << 20, 'Analógico ←'),
  stickRight(1 << 21, 'Analógico →');

  const PadControl(this.bit, this.label);
  final int bit;
  final String label;
}

int xinputMask(int buttons, int lx, int ly, int lt, int rt) {
  const deadzone = 7849;
  var mask = buttons & 0xf3ff;
  if (lx < -deadzone) mask |= PadControl.stickLeft.bit;
  if (lx > deadzone) mask |= PadControl.stickRight.bit;
  if (ly < -deadzone) mask |= PadControl.stickDown.bit;
  if (ly > deadzone) mask |= PadControl.stickUp.bit;
  if (lt > 30) mask |= PadControl.lt.bit;
  if (rt > 30) mask |= PadControl.rt.bit;
  return mask;
}

final class _State extends Struct {
  @Uint32()
  external int packet;
  @Uint16()
  external int buttons;
  @Uint8()
  external int lt;
  @Uint8()
  external int rt;
  @Int16()
  external int lx;
  @Int16()
  external int ly;
  @Int16()
  external int rx;
  @Int16()
  external int ry;
}

typedef _GetState = Uint32 Function(Uint32, Pointer<_State>);

// A subscriber owns one worker. The handshake also handles cancellation
// before the worker has opened the driver.
Stream<List<int?>> watchXInput() {
  final inbox = ReceivePort();
  SendPort? stop;
  var cancelled = false;
  late final StreamController<List<int?>> updates;
  updates = StreamController(
    onListen: () async {
      inbox.listen((message) {
        if (message is SendPort) {
          stop = message;
          if (cancelled) message.send(null);
        } else if (message is List<int?>) {
          if (!cancelled) updates.add(message);
        } else if (message == null) {
          inbox.close();
          updates.close();
        } else if (!cancelled) {
          updates.addError(StateError('XInput indisponível: $message'));
        }
      });
      try {
        await Isolate.spawn(
          _poll,
          inbox.sendPort,
          onExit: inbox.sendPort,
          onError: inbox.sendPort,
        );
      } catch (error) {
        inbox.close();
        if (!cancelled) updates.addError(error);
        await updates.close();
      }
    },
    onCancel: () {
      cancelled = true;
      stop?.send(null);
    },
  );
  return updates.stream;
}

void _poll(SendPort client) {
  final commands = ReceivePort();
  client.send(commands.sendPort);
  Pointer<_State>? buffer;
  DynamicLibrary? library;
  Timer? timer;
  void close() {
    timer?.cancel();
    commands.close();
    if (buffer != null) calloc.free(buffer);
    library?.close();
  }

  commands.listen((_) => close());
  try {
    final system = Platform.environment['SystemRoot'];
    if (!Platform.isWindows || system == null) {
      throw UnsupportedError('Windows');
    }
    library = DynamicLibrary.open('$system/System32/xinput1_4.dll');
    final read = library
        .lookupFunction<_GetState, int Function(int, Pointer<_State>)>(
          'XInputGetState',
        );
    final state = buffer = calloc<_State>();
    final slots = List<int?>.filled(4, null);
    final clock = Stopwatch()..start();
    var nextScan = 0;
    void sample() {
      final now = clock.elapsedMilliseconds;
      final scan = now >= nextScan;
      var changed = nextScan == 0;
      if (scan) nextScan = now + 1000;
      for (var i = 0; i < slots.length; i++) {
        if (!scan && slots[i] == null) continue;
        final value = read(i, state) == 0
            ? xinputMask(
                state.ref.buttons,
                state.ref.lx,
                state.ref.ly,
                state.ref.lt,
                state.ref.rt,
              )
            : null;
        if (slots[i] != value) changed = true;
        slots[i] = value;
      }
      if (changed) client.send(slots);
    }

    sample();
    timer = Timer.periodic(const Duration(milliseconds: 8), (_) => sample());
  } catch (error) {
    client.send(error.toString());
    close();
  }
}
