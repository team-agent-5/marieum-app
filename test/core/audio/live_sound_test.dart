import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/live_sound.dart';

/// 100 ms of a 1 kHz tone at [amplitude], as PCM16 16 kHz mono.
Uint8List _tone(double amplitude) {
  final out = Uint8List(3200);
  final view = ByteData.sublistView(out);
  for (var i = 0; i < 1600; i++) {
    final x = amplitude * math.sin(2 * math.pi * 1000 * i / 16000);
    view.setInt16(i * 2, (x * 32767).round(), Endian.little);
  }
  return out;
}

double _rms(Uint8List chunk) {
  final view = ByteData.sublistView(chunk);
  var sum = 0.0;
  for (var i = 0; i < chunk.length ~/ 2; i++) {
    final x = view.getInt16(i * 2, Endian.little) / 32768;
    sum += x * x;
  }
  return math.sqrt(sum / (chunk.length ~/ 2));
}

void main() {
  group(LiveSound, () {
    test('raises quiet speech and leaves the pause after it alone', () {
      final sound = LiveSound(level: true);
      // Room noise first, so the voice stands out from it.
      for (var i = 0; i < 5; i++) {
        sound.process(_tone(0.002));
      }
      late Uint8List speech;
      for (var i = 0; i < 20; i++) {
        speech = sound.process(_tone(0.02));
      }
      expect(_rms(speech), greaterThan(_rms(_tone(0.02)) * 2));

      final pause = [for (var i = 0; i < 6; i++) sound.process(_tone(0.002))];
      // Within the hold the gain is kept for the quiet end of a word.
      expect(_rms(pause.first), greaterThan(_rms(_tone(0.002)) * 2));
      expect(_rms(pause.last), closeTo(_rms(_tone(0.002)), 0.0002));
    });

    test('leaves the level alone when levelling is off', () {
      final sound = LiveSound();
      late Uint8List out;
      for (var i = 0; i < 10; i++) {
        out = sound.process(_tone(0.02));
      }
      expect(_rms(out), closeTo(_rms(_tone(0.02)), 0.0005));
    });
  });
}
