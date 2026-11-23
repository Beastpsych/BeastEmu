// Optional stdin extension. Each command is exactly one byte.
// 0..100 retain the v1 volume contract. TCP stays RGBA / little-endian joypad.
const sameBoyCommandEnvironment = 'BEASTEMU_COMMANDS_V2';
const expectedRomEnvironment = 'BEASTEMU_EXPECTED_ROM_SHA256';
const stateReplyPrefix = 'BEASTEMU_STATE ';
const listStateSlots = 128;
const createStateBase = 128; // Add a slot number (1..5).
const replaceStateBase = 133;
const loadStateBase = 138;
bool isStateCommand(int byte) =>
    (byte >= listStateSlots && byte <= loadStateBase + 5) ||
    byte == quickSave ||
    byte == quickLoad;

const quickSave = 148;
const quickLoad = 149;

class EmptyQuickSlot implements Exception {
  const EmptyQuickSlot();
}

const speedNormal = 144;
const speedDouble = 145;
const speedTriple = 146;
const speedQuad = 147;
