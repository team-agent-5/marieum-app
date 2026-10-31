import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';
import 'package:marieum_app/features/settings/domain/repositories/settings_repository.dart';

class SettingsState extends Equatable {
  const SettingsState(this.settings, {this.failure});
  final AppSettings settings;
  final Failure? failure;
  @override
  List<Object?> get props => [settings, failure];
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._repository) : super(SettingsState(_repository.initial));
  final SettingsRepository _repository;
  int _revision = 0;
  Future<void> setRate(TtsRate rate) =>
      _change(state.settings.copyWith(rate: rate));
  Future<void> setVolume(TtsVolume volume) =>
      _change(state.settings.copyWith(volume: volume));
  Future<void> setLargeText({required bool value}) =>
      _change(state.settings.copyWith(largeText: value));
  Future<void> _change(AppSettings settings) async {
    if (settings == state.settings || isClosed) return;
    final revision = ++_revision;
    emit(SettingsState(settings));
    final result = await _repository.save(settings);
    if (isClosed || revision != _revision) return;
    if (result case FailureResult(:final failure)) {
      emit(SettingsState(settings, failure: failure));
    }
  }
}
