import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/recorder.dart';

List<int> _tone(int amplitude, {int samples = 1600}) {
  final data = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    data.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  group('pcmLevel', () {
    test('is zero for silence and empty chunks', () {
      expect(pcmLevel(const []), 0);
      expect(pcmLevel(_tone(0)), 0);
    });

    test('rises with loudness and stays within 0..1', () {
      final quiet = pcmLevel(_tone(300));
      final loud = pcmLevel(_tone(20000));
      expect(quiet, greaterThan(0));
      expect(loud, greaterThan(quiet));
      expect(pcmLevel(_tone(32767)), lessThanOrEqualTo(1));
    });
  });
}
