import 'package:marieum_app/core/tts/tts_port.dart';

abstract final class TtsMapping {
  static double rate(VoicePlatform platform, TtsRate rate) =>
      switch (platform) {
        VoicePlatform.ios => switch (rate) {
          TtsRate.slow => 0.38,
          TtsRate.normal => 0.5,
          TtsRate.fast => 0.6,
        },
        // flutter_tts doubles this on Android, so 0.5 is the engine's 1.0.
        VoicePlatform.android => switch (rate) {
          TtsRate.slow => 0.35,
          TtsRate.normal => 0.5,
          TtsRate.fast => 0.65,
        },
      };

  static double volume(TtsVolume volume) => switch (volume) {
    TtsVolume.soft => 0.5,
    TtsVolume.normal => 0.8,
    TtsVolume.loud => 1.0,
  };
}
