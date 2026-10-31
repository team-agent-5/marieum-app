import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';

Map<String, Object> settingsPayload(AppSettings settings) => {
  'tts_rate': settings.rate.name,
  'tts_volume': switch (settings.volume) {
    TtsVolume.soft => 'low',
    TtsVolume.normal => 'normal',
    TtsVolume.loud => 'high',
  },
  'large_text': settings.largeText,
};
