/// Independent helper stdin protocol (v1). One unsigned byte is one complete
/// command: 0..100 sets the effective volume; other values are reserved.
const sameBoyVolumeEnvironment = 'BEASTEMU_VOLUME_V1';

int? latestVolume(List<int> bytes) {
  for (var i = bytes.length - 1; i >= 0; i--) {
    final value = bytes[i];
    if (value >= 0 && value <= 100) return value;
  }
  return null;
}
