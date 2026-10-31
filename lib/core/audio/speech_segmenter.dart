import 'dart:typed_data';

import 'package:marieum_app/core/audio/recorder.dart';

sealed class SegmentSignal {
  const SegmentSignal(this.audio);
  final Uint8List audio;
}

/// Voice began; [audio] includes the lead-in kept before it.
final class SegmentStarted extends SegmentSignal {
  const SegmentStarted(super.audio);
}

final class SegmentContinued extends SegmentSignal {
  const SegmentContinued(super.audio);
}

/// A pause or the length limit ended the segment. [kept] is false when it
/// was too short to be speech.
final class SegmentEnded extends SegmentSignal {
  const SegmentEnded(super.audio, {required this.kept});
  final bool kept;
}

/// Splits a continuous PCM16 16 kHz mono stream into utterances: a segment
/// starts when the input gets loud and ends after a pause, and its audio is
/// handed on as it arrives so it can be streamed while the patient talks.
class SpeechSegmenter {
  SpeechSegmenter({
    this.threshold = defaultThreshold,
    this.minSpeech = const Duration(milliseconds: 300),
    this.endSilence = const Duration(milliseconds: 700),
    this.maxSegment = const Duration(seconds: 8),
    this.preRoll = const Duration(milliseconds: 300),
  });

  static const defaultThreshold = 0.35;

  /// [pcmLevel] at or above this counts as voice.
  final double threshold;
  final Duration minSpeech;
  final Duration endSilence;
  final Duration maxSegment;

  /// Audio kept from before the voice starts so first syllables survive.
  final Duration preRoll;

  static const int _bytesPerMs = Recorder.bytesPerSecond ~/ 1000;

  final _before = <Uint8List>[];
  var _beforeBytes = 0;
  var _inSegment = false;
  var _lengthMs = 0;
  var _speechMs = 0;
  var _silenceMs = 0;

  /// Whether the current input is voice.
  bool get hearing => _inSegment && _silenceMs == 0;

  /// Feeds one chunk; returns what it means for the segment, or null while
  /// there is no voice.
  SegmentSignal? add(Uint8List chunk, {double? level}) {
    final loud = (level ?? pcmLevel(chunk)) >= threshold;
    final chunkMs = chunk.length ~/ _bytesPerMs;
    if (!_inSegment) {
      if (!loud) {
        _keepBefore(chunk);
        return null;
      }
      final audio = BytesBuilder(copy: false);
      _before
        ..forEach(audio.add)
        ..clear();
      audio.add(chunk);
      _beforeBytes = 0;
      _inSegment = true;
      _lengthMs = audio.length ~/ _bytesPerMs;
      _speechMs = chunkMs;
      _silenceMs = 0;
      return SegmentStarted(audio.takeBytes());
    }
    _lengthMs += chunkMs;
    if (loud) {
      _speechMs += chunkMs;
      _silenceMs = 0;
    } else {
      _silenceMs += chunkMs;
    }
    if (_silenceMs < endSilence.inMilliseconds &&
        _lengthMs < maxSegment.inMilliseconds) {
      return SegmentContinued(chunk);
    }
    final kept = _speechMs >= minSpeech.inMilliseconds;
    reset();
    return SegmentEnded(chunk, kept: kept);
  }

  /// Drops anything in progress, e.g. while the app itself is speaking.
  void reset() {
    _before.clear();
    _beforeBytes = 0;
    _inSegment = false;
    _lengthMs = 0;
    _speechMs = 0;
    _silenceMs = 0;
  }

  void _keepBefore(Uint8List chunk) {
    _before.add(chunk);
    _beforeBytes += chunk.length;
    final limit = preRoll.inMilliseconds * _bytesPerMs;
    while (_before.length > 1 && _beforeBytes - _before.first.length >= limit) {
      _beforeBytes -= _before.removeAt(0).length;
    }
  }
}
