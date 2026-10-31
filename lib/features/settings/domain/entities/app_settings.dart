import 'package:equatable/equatable.dart';
import 'package:marieum_app/core/tts/tts_port.dart';

class AppSettings extends Equatable {
  const AppSettings({
    this.rate = TtsRate.normal,
    this.volume = TtsVolume.normal,
    this.largeText = false,
    this.voiceId,
  });
  final TtsRate rate;
  final TtsVolume volume;
  final bool largeText;
  final String? voiceId;
  static const _unchanged = Object();
  AppSettings copyWith({
    TtsRate? rate,
    TtsVolume? volume,
    bool? largeText,
    Object? voiceId = _unchanged,
  }) => AppSettings(
    rate: rate ?? this.rate,
    volume: volume ?? this.volume,
    largeText: largeText ?? this.largeText,
    voiceId: identical(voiceId, _unchanged) ? this.voiceId : voiceId as String?,
  );
  @override
  List<Object?> get props => [rate, volume, largeText, voiceId];
}
