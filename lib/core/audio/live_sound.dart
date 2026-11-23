import 'dart:math' as math;
import 'dart:typed_data';

/// Shapes live microphone audio before it is sent. Rumble below about
/// 80 Hz, from handling and air, is removed. With [level] on, speech is
/// raised toward a steady level measured from the patient's voice alone,
/// by at most 12 dB, since each phone's microphone records at a different
/// level. Pauses are left at their own level once speech has been gone for
/// [_hold], so raised room noise does not keep the recognizer from hearing
/// a sentence end. Only peaks above the knee are rounded off.
class LiveSound {
  LiveSound({this.level = false});

  final bool level;

  /// Speech level aimed for, about -20 dBFS.
  static const _targetRms = 0.1;
  static const _maxGain = 4.0;
  static const _knee = 0.7;

  /// Samples of 16 kHz audio without speech before the gain eases back,
  /// 300 ms, so the quiet ends of words keep it.
  static const _hold = 4800;

  /// One-pole high-pass at 80 Hz for 16 kHz audio.
  static final double _pole = math.exp(-2 * math.pi * 80 / 16000);

  double _lastIn = 0;
  double _lastOut = 0;
  double? _noise;
  double? _speech;
  double _gain = 1;

  /// The gain applied at the end of the last chunk, eased toward the next.
  double _applied = 1;
  int _sinceSpeech = _hold;

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
    var target = 1.0;
    if (level) {
      if (_adapt(math.sqrt(sum / count))) {
        _sinceSpeech = 0;
      } else {
        _sinceSpeech += count;
      }
      if (_sinceSpeech < _hold) target = _gain;
    }
    final from = _applied;
    _applied = target;
    final out = Uint8List(count * 2);
    final view = ByteData.sublistView(out);
    for (var i = 0; i < count; i++) {
      final x = samples[i] * (from + (target - from) * (i + 1) / count);
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
  /// the gain moves slowly so it does not pump within a sentence. Returns
  /// whether the chunk held speech.
  bool _adapt(double rms) {
    final noise = _noise;
    _noise = noise == null || rms < noise ? rms : noise * 1.002;
    if (rms < math.max((_noise ?? 0) * 3, 0.01)) return false;
    final speech = _speech;
    _speech = speech == null ? rms : speech * 0.9 + rms * 0.1;
    final target = (_targetRms / _speech!).clamp(1.0, _maxGain);
    _gain += (target - _gain) * 0.2;
    return true;
  }

  static double _tanh(double x) {
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }
}
