import 'dart:math' as math;
import 'dart:typed_data';

/// Shapes live microphone audio before it is sent. Rumble below about
/// 80 Hz, from handling and air, is removed. With [level] on, speech is
/// raised toward a steady level measured from the patient's voice alone,
/// by at most 12 dB, since each phone's microphone records at a different
/// level. Only peaks above the knee are rounded off.
class LiveSound {
  LiveSound({this.level = false});

  final bool level;

  /// Speech level aimed for, about -20 dBFS.
  static const _targetRms = 0.1;
  static const _maxGain = 4.0;
  static const _knee = 0.7;

  /// One-pole high-pass at 80 Hz for 16 kHz audio.
  static final double _pole = math.exp(-2 * math.pi * 80 / 16000);

  double _lastIn = 0;
  double _lastOut = 0;
  double? _noise;
  double? _speech;
  double _gain = 1;

  Uint8List process(Uint8List chunk) {
    final count = chunk.length ~/ 2;
    if (count == 0) return chunk;
    final input = ByteData.sublistView(chunk);
    final samples = Float64List(count);
    var sum = 0.0;
    for (var i = 0; i < count; i++) {
      final x = input.getInt16(i * 2, Endian.little) / 32768;
      _lastOut = _pole * (_lastOut + x - _lastIn);
      _lastIn = x;
      samples[i] = _lastOut;
      sum += _lastOut * _lastOut;
    }
    if (level) _adapt(math.sqrt(sum / count));
    final out = Uint8List(count * 2);
    final view = ByteData.sublistView(out);
    for (var i = 0; i < count; i++) {
      final x = samples[i] * _gain;
      final a = x.abs();
      final y = a <= _knee
          ? x
          : (_knee + (1 - _knee) * _tanh((a - _knee) / (1 - _knee))) * x.sign;
      view.setInt16(
        i * 2,
        (y * 32767).round().clamp(-32768, 32767),
        Endian.little,
      );
    }
    return out;
  }

  /// Follows the quietest level as noise and the voice above it as speech;
  /// the gain moves slowly so it does not pump within a sentence.
  void _adapt(double rms) {
    final noise = _noise;
    _noise = noise == null || rms < noise ? rms : noise * 1.002;
    if (rms < math.max((_noise ?? 0) * 3, 0.01)) return;
    final speech = _speech;
    _speech = speech == null ? rms : speech * 0.9 + rms * 0.1;
    final target = (_targetRms / _speech!).clamp(1.0, _maxGain);
    _gain += (target - _gain) * 0.2;
  }

  static double _tanh(double x) {
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }
}
