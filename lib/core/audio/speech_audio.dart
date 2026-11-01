import 'dart:math' as math;
import 'dart:typed_data';

import 'package:marieum_app/core/audio/recorded_audio.dart';

/// A recording tidied before upload: silence before and after the speech
/// is cut, since the recognizer tends to invent words in it, and quiet
/// speech is raised, since each phone's microphone records at a different
/// level. Quiet but present speech is never cut.
class TidiedSpeech {
  const TidiedSpeech(
    this.audio, {
    required this.trimmedMs,
    required this.gainDb,
  });
  final RecordedAudio audio;
  final int trimmedMs;
  final double gainDb;
}

abstract final class SpeechAudio {
  /// 20 ms of PCM16 16 kHz mono.
  static const _frameBytes = 640;
  static const _frameMs = 20;

  /// Kept around the speech so soft first and last sounds survive.
  static const padMs = 400;

  /// Speech level aimed for, about -20 dBFS.
  static const _targetRms = 0.1;

  /// Raised by at most 12 dB and never lowered.
  static const _maxGain = 4.0;

  /// Peaks stay under this after raising.
  static const _peakLimit = 0.9;

  static TidiedSpeech tidy(RecordedAudio audio) {
    const header = 44;
    if (audio.bytes.length <= header + _frameBytes) {
      return TidiedSpeech(audio, trimmedMs: 0, gainDb: 0);
    }
    final pcm = ByteData.sublistView(audio.bytes, header);
    final samples = pcm.lengthInBytes ~/ 2;
    const frameSamples = _frameBytes ~/ 2;
    final frames = samples ~/ frameSamples;
    final levels = List<double>.generate(frames, (f) {
      var sum = 0.0;
      for (var i = f * frameSamples; i < (f + 1) * frameSamples; i++) {
        final s = pcm.getInt16(i * 2, Endian.little) / 32768;
        sum += s * s;
      }
      return math.sqrt(sum / frameSamples);
    });
    final sorted = [...levels]..sort();
    final noise = sorted[(sorted.length * 0.2).floor()];
    final voice = math.max(noise * 3, 0.01);
    if (!levels.any((l) => l >= voice)) {
      return TidiedSpeech(audio, trimmedMs: 0, gainDb: 0);
    }
    // Edges use a lower bar than the speech level so a soft start or
    // trailing sound is not taken for silence.
    final edge = math.max(noise * 2, 0.005);
    final first = levels.indexWhere((l) => l >= edge);
    final last = levels.lastIndexWhere((l) => l >= edge);
    const pad = padMs ~/ _frameMs;
    final start = math.max(0, first - pad) * frameSamples;
    final end = math.min(samples, (last + 1 + pad) * frameSamples);

    var speechSum = 0.0;
    var speechFrames = 0;
    var peak = 0.0;
    for (var f = first; f <= last; f++) {
      if (levels[f] < voice) continue;
      speechSum += levels[f] * levels[f];
      speechFrames++;
    }
    for (var i = start; i < end; i++) {
      final s = (pcm.getInt16(i * 2, Endian.little) / 32768).abs();
      if (s > peak) peak = s;
    }
    final speechRms = math.sqrt(speechSum / math.max(1, speechFrames));
    var gain = speechRms > 0 ? _targetRms / speechRms : 1.0;
    gain = gain.clamp(1.0, _maxGain);
    if (peak > 0) gain = math.min(gain, math.max(1, _peakLimit / peak));

    final out = Uint8List((end - start) * 2);
    final view = ByteData.sublistView(out);
    for (var i = start; i < end; i++) {
      final s = pcm.getInt16(i * 2, Endian.little) * gain;
      view.setInt16(
        (i - start) * 2,
        s.round().clamp(-32768, 32767),
        Endian.little,
      );
    }
    return TidiedSpeech(
      encodePcmWav(out),
      trimmedMs: (samples - (end - start)) * 1000 ~/ 16000,
      gainDb: 20 * math.log(gain) / math.ln10,
    );
  }
}
