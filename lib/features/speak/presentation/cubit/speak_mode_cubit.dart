import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/speak/domain/entities/speak_mode.dart';
import 'package:marieum_app/features/speak/domain/repositories/speak_mode_repository.dart';

class SpeakModeState extends Equatable {
  const SpeakModeState(this.mode, {this.failure});
  final SpeakMode mode;
  final Failure? failure;
  @override
  List<Object?> get props => [mode, failure];
}

class SpeakModeCubit extends Cubit<SpeakModeState> {
  SpeakModeCubit(this._repository)
    : super(SpeakModeState(_repository.initialMode));
  final SpeakModeRepository _repository;
  int _revision = 0;
  Future<void> select(SpeakMode mode) async {
    if (isClosed || (mode == state.mode && state.failure == null)) return;
    final revision = ++_revision;
    emit(SpeakModeState(mode));
    final result = await _repository.save(mode);
    if (isClosed || revision != _revision) return;
    if (result case FailureResult(:final failure)) {
      emit(SpeakModeState(mode, failure: failure));
    }
  }
}
