import 'package:equatable/equatable.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/tts/tts_port.dart';

class AppSettings extends Equatable {
  const AppSettings({
    this.rate = TtsRate.normal,
    this.volume = TtsVolume.normal,
    this.largeText = false,
  });
  final TtsRate rate;
  final TtsVolume volume;
  final bool largeText;
  AppSettings copyWith({TtsRate? rate, TtsVolume? volume, bool? largeText}) =>
      AppSettings(
        rate: rate ?? this.rate,
        volume: volume ?? this.volume,
        largeText: largeText ?? this.largeText,
      );
  @override
  List<Object?> get props => [rate, volume, largeText];
}

abstract interface class SettingsRepository {
  AppSettings get initial;
  Future<Result<void>> save(AppSettings settings);
}
