import 'package:equatable/equatable.dart';
import 'package:marieum_app/core/audio/speech_pace.dart';
import 'package:marieum_app/core/tts/cloud_voice.dart';
import 'package:marieum_app/core/tts/tts_port.dart';

class AppSettings extends Equatable {
  const AppSettings({
    this.rate = TtsRate.normal,
    this.volume = TtsVolume.normal,
    this.largeText = false,
    this.voiceId,
    this.cloudVoice = CloudVoice.female,
    this.speechPace = SpeechPace.auto,
  });
  final TtsRate rate;
  final TtsVolume volume;
  final bool largeText;
  final String? voiceId;
  final CloudVoice cloudVoice;

  /// How fast the patient speaks, for listening to them.
  final SpeechPace speechPace;
  static const _unchanged = Object();
  AppSettings copyWith({
    TtsRate? rate,
    TtsVolume? volume,
    bool? largeText,
    Object? voiceId = _unchanged,
    CloudVoice? cloudVoice,
    SpeechPace? speechPace,
  }) => AppSettings(
    rate: rate ?? this.rate,
    volume: volume ?? this.volume,
    largeText: largeText ?? this.largeText,
    voiceId: identical(voiceId, _unchanged) ? this.voiceId : voiceId as String?,
    cloudVoice: cloudVoice ?? this.cloudVoice,
    speechPace: speechPace ?? this.speechPace,
  );
  @override
  List<Object?> get props => [
    rate,
    volume,
    largeText,
    voiceId,
    cloudVoice,
    speechPace,
  ];
}
