import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/speech_segmenter.dart';

void main() {
  // 100 ms of PCM16 16 kHz mono.
  Uint8List chunk() => Uint8List(3200);

  group(SpeechSegmenter, () {
    late SpeechSegmenter segmenter;

    setUp(() => segmenter = SpeechSegmenter());

    List<SegmentSignal> feed(double level, [int count = 1]) => [
      for (var i = 0; i < count; i++) ?segmenter.add(chunk(), level: level),
    ];

    int bytes(List<SegmentSignal> signals) =>
        signals.fold(0, (sum, s) => sum + s.audio.length);

    test('streams a segment from its lead-in to the pause', () {
      expect(feed(0.1, 5), isEmpty);
      final voice = feed(0.6, 6);
      expect(voice.first, isA<SegmentStarted>());
      // 300 ms lead-in plus the first voice chunk.
      expect(voice.first.audio.length, 3200 * 4);
      expect(voice.skip(1), everyElement(isA<SegmentContinued>()));
      expect(segmenter.hearing, isTrue);
      final pause = feed(0.1, 7);
      expect(pause.last, isA<SegmentEnded>());
      expect((pause.last as SegmentEnded).kept, isTrue);
      // 300 ms lead-in + 600 ms voice + 700 ms pause.
      expect(bytes([...voice, ...pause]), 3200 * 16);
      expect(segmenter.hearing, isFalse);
    });

    test('marks a click shorter than the minimum speech as not kept', () {
      feed(0.6, 2);
      final ended = feed(0.1, 7).last as SegmentEnded;
      expect(ended.kept, isFalse);
    });

    test('ends long speech at the maximum segment length', () {
      expect(feed(0.7, 80).whereType<SegmentEnded>(), hasLength(1));
    });

    test('reset drops the segment in progress', () {
      feed(0.7, 5);
      segmenter.reset();
      expect(feed(0.1, 7), isEmpty);
    });
  });
}
