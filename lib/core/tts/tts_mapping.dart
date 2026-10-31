import 'package:marieum_app/core/tts/tts_port.dart';

abstract final class TtsMapping {
  static double rate(VoicePlatform platform, TtsRate rate) =>
      switch (platform) {
        VoicePlatform.ios => switch (rate) {
          TtsRate.slow => 0.38,
          TtsRate.normal => 0.5,
          TtsRate.fast => 0.6,
        },
        VoicePlatform.android => switch (rate) {
          TtsRate.slow => 0.7,
          TtsRate.normal => 1.0,
          TtsRate.fast => 1.3,
        },
      };

  static double volume(TtsVolume volume) => switch (volume) {
    TtsVolume.soft => 0.5,
    TtsVolume.normal => 0.8,
    TtsVolume.loud => 1.0,
  };
}
