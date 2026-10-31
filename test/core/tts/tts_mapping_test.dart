import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/tts/tts_mapping.dart';
import 'package:marieum_app/core/tts/tts_port.dart';

void main() {
  group(TtsMapping, () {
    for (final entry in {
      VoicePlatform.ios: [0.38, 0.5, 0.6],
      VoicePlatform.android: [0.35, 0.5, 0.65],
    }.entries) {
      for (final rate in TtsRate.values) {
        test('maps ${entry.key} $rate to the approved engine rate', () {
          expect(TtsMapping.rate(entry.key, rate), entry.value[rate.index]);
        });
      }
    }
    for (final volume in TtsVolume.values) {
      test('maps $volume into the native volume range', () {
        expect(TtsMapping.volume(volume), [0.5, 0.8, 1.0][volume.index]);
      });
    }
  });
}
