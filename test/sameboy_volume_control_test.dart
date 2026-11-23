import 'package:beastemu/services/sameboy_volume_control.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cada byte de volume e independente das fronteiras do pipe', () {
    int process(List<List<int>> chunks) {
      var volume = 100;
      for (final chunk in chunks) {
        volume = latestVolume(chunk) ?? volume;
      }
      return volume;
    }

    expect(process([[0]]), 0);
    expect(process([[0, 26, 44, 255]]), 44);
    expect(process([[0], [26], [44], [255]]), 44);
    expect(process([[20], [], [100]]), 100);
    expect(latestVolume([101, 255]), isNull);
  });
}
