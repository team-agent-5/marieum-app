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
///
/// "Loud" is measured against the room: the voice threshold sits a margin
/// above the recent noise floor, so quiet voices are heard in a quiet room
/// and steady noise is not taken for speech.
class SpeechSegmenter {
  SpeechSegmenter({
    this.margin = 0.2,
    this.minThreshold = 0.25,
    this.maxThreshold = 0.6,
    this.noiseWindow = const Duration(seconds: 5),
    this.minSpeech = const Duration(milliseconds: 300),
    this.endSilence = const Duration(milliseconds: 1300),
    this.maxSegment = const Duration(seconds: 8),
    this.preRoll = const Duration(milliseconds: 600),
  });

  /// Used until enough of the room has been heard.
  static const defaultThreshold = 0.35;

  /// Voice must be this far above the noise floor; 0.2 of [pcmLevel] is
  /// 10 dB.
  final double margin;
  final double minThreshold;
  final double maxThreshold;

  /// How much recent input the noise floor is taken from.
  final Duration noiseWindow;
  final Duration minSpeech;

  /// Dysarthric speech pauses long between words; shorter values split one
  /// sentence into several.
  final Duration endSilence;
  final Duration maxSegment;

  /// Audio kept from before the voice starts so first syllables survive.
  final Duration preRoll;

  static const int _bytesPerMs = Recorder.bytesPerSecond ~/ 1000;

  final _before = <Uint8List>[];
  var _beforeBytes = 0;
  final _recent = <({double level, int ms})>[];
  var _recentMs = 0;
  double _threshold = defaultThreshold;
  var _inSegment = false;
  var _lengthMs = 0;
  var _speechMs = 0;
  var _silenceMs = 0;

  /// [pcmLevel] at or above this counts as voice.
  double get threshold {
    final floor = playbackFloor;
    return floor != null && floor > _threshold ? floor : _threshold;
  }

  /// While the app is speaking, only input above this counts as voice so
  /// its own playback is not taken for the patient.
  double? playbackFloor;

  /// Whether the current input is voice.
  bool get hearing => _inSegment && _silenceMs == 0;

  /// Feeds one chunk; returns what it means for the segment, or null while
  /// there is no voice.
  SegmentSignal? add(Uint8List chunk, {double? level}) {
    final value = level ?? pcmLevel(chunk);
    final chunkMs = chunk.length ~/ _bytesPerMs;
    _listen(value, chunkMs);
    if (!_inSegment) {
      // While the app speaks only a voice above its own starts a segment.
      if (value < threshold) {
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
    // A segment already under way keeps the room threshold, so the patient
    // is not cut off when the app starts speaking.
    if (value >= _threshold) {
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

  /// Tracks the noise floor as a low percentile of recent input: speech
  /// always has gaps, so the quiet end of the window is the room itself.
  void _listen(double level, int ms) {
    _recent.add((level: level, ms: ms));
    _recentMs += ms;
    while (_recent.length > 1 &&
        _recentMs - _recent.first.ms >= noiseWindow.inMilliseconds) {
      _recentMs -= _recent.removeAt(0).ms;
    }
    if (_recentMs < 1000) return;
    final levels = [for (final r in _recent) r.level]..sort();
    final floor = levels[levels.length ~/ 10];
    _threshold = (floor + margin).clamp(minThreshold, maxThreshold);
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
