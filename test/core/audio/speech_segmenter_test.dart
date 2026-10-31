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
      expect(feed(0.1, 10), isEmpty);
      final voice = feed(0.6, 6);
      expect(voice.first, isA<SegmentStarted>());
      // 600 ms lead-in plus the first voice chunk.
      expect(voice.first.audio.length, 3200 * 7);
      expect(voice.skip(1), everyElement(isA<SegmentContinued>()));
      expect(segmenter.hearing, isTrue);
      final pause = feed(0.1, 13);
      expect(pause.last, isA<SegmentEnded>());
      expect((pause.last as SegmentEnded).kept, isTrue);
      // 600 ms lead-in + 600 ms voice + 1.3 s pause.
      expect(bytes([...voice, ...pause]), 3200 * 25);
      expect(segmenter.hearing, isFalse);
    });

    test('marks a click shorter than the minimum speech as not kept', () {
      feed(0.6, 2);
      final ended = feed(0.1, 13).last as SegmentEnded;
      expect(ended.kept, isFalse);
    });

    test('ends long speech at the maximum segment length', () {
      expect(feed(0.7, 80).whereType<SegmentEnded>(), hasLength(1));
    });

    test('raises the voice threshold over steady noise', () {
      feed(0.45, 50);
      // 5 s of a 0.45 hum: the floor is the hum, voice must clear it by 10 dB.
      expect(segmenter.threshold, closeTo(0.6, 1e-9));
      final signals = feed(0.45, 10);
      expect(signals.whereType<SegmentStarted>(), isEmpty);
    });

    test('hears a quiet voice in a quiet room', () {
      feed(0.02, 20);
      expect(segmenter.threshold, closeTo(0.25, 1e-9));
      expect(feed(0.3).single, isA<SegmentStarted>());
    });

    test('keeps the room level across a reset', () {
      feed(0.02, 20);
      segmenter.reset();
      expect(segmenter.threshold, closeTo(0.25, 1e-9));
    });

    test('needs louder input than the app while it speaks', () {
      feed(0.02, 20);
      segmenter.playbackFloor = 0.5;
      expect(segmenter.threshold, 0.5);
      expect(feed(0.4), isEmpty);
      expect(feed(0.6).single, isA<SegmentStarted>());
      segmenter
        ..reset()
        ..playbackFloor = null;
      expect(segmenter.threshold, closeTo(0.25, 1e-9));
    });

    test('keeps a segment under way going when the app starts speaking', () {
      feed(0.02, 20);
      expect(feed(0.4).single, isA<SegmentStarted>());
      segmenter.playbackFloor = 0.6;
      final signals = feed(0.4, 15);
      expect(signals, everyElement(isA<SegmentContinued>()));
    });

    test('reset drops the segment in progress', () {
      feed(0.7, 5);
      segmenter.reset();
      expect(feed(0.1, 10), isEmpty);
    });
  });
}
