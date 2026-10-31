import 'package:equatable/equatable.dart';

enum TtsVoiceQuality { premium, enhanced, high, normal, unknown }

class TtsVoice extends Equatable {
  const TtsVoice({
    required this.id,
    required this.name,
    required this.locale,
    required this.quality,
    required this.requiresNetwork,
  });

  final String id;
  final String name;
  final String locale;
  final TtsVoiceQuality quality;
  final bool requiresNetwork;

  bool get isHighQuality => switch (quality) {
    TtsVoiceQuality.premium ||
    TtsVoiceQuality.enhanced ||
    TtsVoiceQuality.high => true,
    TtsVoiceQuality.normal || TtsVoiceQuality.unknown => false,
  };

  @override
  List<Object?> get props => [id, name, locale, quality, requiresNetwork];
}
