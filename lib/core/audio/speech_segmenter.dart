import 'dart:typed_data';

import 'package:marieum_app/core/audio/recorder.dart';

/// Splits a continuous PCM16 16 kHz mono stream into utterances: a segment
/// starts when the input gets loud and ends after a pause, so each one can
/// be interpreted while the patient keeps talking.
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
  final _segment = BytesBuilder(copy: false);
  var _inSegment = false;
  var _speechMs = 0;
  var _silenceMs = 0;

  /// Whether the current input is voice.
  bool get hearing => _inSegment && _silenceMs == 0;

  /// Feeds one chunk; returns a finished segment when a pause ends one.
  Uint8List? add(Uint8List chunk, {double? level}) {
    final loud = (level ?? pcmLevel(chunk)) >= threshold;
    final chunkMs = chunk.length ~/ _bytesPerMs;
    if (!_inSegment) {
      if (!loud) {
        _keepBefore(chunk);
        return null;
      }
      _inSegment = true;
      _before
        ..forEach(_segment.add)
        ..clear();
      _beforeBytes = 0;
      _segment.add(chunk);
      _speechMs = chunkMs;
      _silenceMs = 0;
      return null;
    }
    _segment.add(chunk);
    if (loud) {
      _speechMs += chunkMs;
      _silenceMs = 0;
    } else {
      _silenceMs += chunkMs;
    }
    final lengthMs = _segment.length ~/ _bytesPerMs;
    if (_silenceMs < endSilence.inMilliseconds &&
        lengthMs < maxSegment.inMilliseconds) {
      return null;
    }
    final enough = _speechMs >= minSpeech.inMilliseconds;
    final bytes = _segment.takeBytes();
    reset();
    return enough ? bytes : null;
  }

  /// Drops anything in progress, e.g. while the app itself is speaking.
  void reset() {
    _segment.clear();
    _before.clear();
    _beforeBytes = 0;
    _inSegment = false;
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
