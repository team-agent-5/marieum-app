import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/core/tts/tts_voice.dart';
import 'package:marieum_app/core/tts/tts_voice_selector.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';
import 'package:marieum_app/features/settings/domain/repositories/settings_repository.dart';

class SettingsState extends Equatable {
  const SettingsState(this.settings, {this.failure, this.voices});
  final AppSettings settings;
  final Failure? failure;
  final List<TtsVoice>? voices;
  @override
  List<Object?> get props => [settings, failure, voices];
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._repository, {required this.voices})
    : super(SettingsState(_repository.initial));
  final SettingsRepository _repository;
  final TtsVoiceSelector voices;
  int _revision = 0;
  Future<void> setRate(TtsRate rate) =>
      _change(state.settings.copyWith(rate: rate));
  Future<void> setVolume(TtsVolume volume) =>
      _change(state.settings.copyWith(volume: volume));
  Future<void> setLargeText({required bool value}) =>
      _change(state.settings.copyWith(largeText: value));
  Future<void> setVoice(String? id) =>
      _change(state.settings.copyWith(voiceId: id));

  Future<void> loadVoices() async {
    if (state.voices != null || isClosed) return;
    List<TtsVoice> available;
    try {
      available = await voices.availableVoices();
    } on Object {
      available = const [];
    }
    if (isClosed) return;
    emit(
      SettingsState(state.settings, failure: state.failure, voices: available),
    );
  }

  Future<void> previewVoice(String? id, Future<void> Function() play) async {
    try {
      await voices.selectVoice(id);
      await play();
    } finally {
      await voices.selectVoice(state.settings.voiceId);
    }
  }

  Future<void> _change(AppSettings settings) async {
    if (settings == state.settings || isClosed) return;
    final revision = ++_revision;
    emit(SettingsState(settings, voices: state.voices));
    final result = await _repository.save(settings);
    if (isClosed || revision != _revision) return;
    if (result case FailureResult(:final failure)) {
      emit(SettingsState(settings, failure: failure, voices: state.voices));
    }
  }
}
