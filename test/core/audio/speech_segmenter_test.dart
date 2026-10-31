import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/speech_segmenter.dart';

void main() {
  // 100 ms of PCM16 16 kHz mono.
  Uint8List chunk() => Uint8List(3200);

  group(SpeechSegmenter, () {
    late SpeechSegmenter segmenter;

    setUp(() => segmenter = SpeechSegmenter());

    Uint8List? feed(double level, [int count = 1]) {
      Uint8List? out;
      for (var i = 0; i < count; i++) {
        out = segmenter.add(chunk(), level: level) ?? out;
      }
      return out;
    }

    test('cuts a segment after a pause and keeps a little lead-in', () {
      expect(feed(0.1, 5), isNull);
      expect(feed(0.6, 6), isNull);
      expect(segmenter.hearing, isTrue);
      final segment = feed(0.1, 7);
      expect(segment, isNotNull);
      // 300 ms lead-in + 600 ms voice + 700 ms pause.
      expect(segment!.length, 3200 * 16);
      expect(segmenter.hearing, isFalse);
    });

    test('ignores a click shorter than the minimum speech', () {
      feed(0.6, 2);
      expect(feed(0.1, 7), isNull);
    });

    test('splits long speech at the maximum segment length', () {
      expect(feed(0.7, 80), isNotNull);
    });

    test('reset drops the segment in progress', () {
      feed(0.7, 5);
      segmenter.reset();
      expect(feed(0.1, 7), isNull);
    });
  });
}
