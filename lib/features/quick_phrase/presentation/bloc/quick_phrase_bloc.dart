import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/quick_phrase.dart';
import 'package:marieum_app/features/quick_phrase/domain/repositories/quick_phrase_repository.dart';

enum QuickPhraseStatus { idle, saving, saved, failure }

sealed class QuickPhraseEvent extends Equatable {
  const QuickPhraseEvent();
  @override
  List<Object?> get props => [];
}

final class QuickPhraseUsed extends QuickPhraseEvent {
  const QuickPhraseUsed(this.phrase);
  final QuickPhrase phrase;
  @override
  List<Object?> get props => [phrase];
}

final class QuickPhraseAdded extends QuickPhraseEvent {
  const QuickPhraseAdded(this.text);
  final String text;
  @override
  List<Object?> get props => [text];
}

final class QuickPhraseRemoved extends QuickPhraseEvent {
  const QuickPhraseRemoved(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

class QuickPhraseState extends Equatable {
  const QuickPhraseState({
    required this.phrases,
    this.status = QuickPhraseStatus.idle,
    this.failure,
  });
  final List<QuickPhrase> phrases;
  final QuickPhraseStatus status;
  final Failure? failure;

  bool get canRemove => phrases.length > QuickPhraseRules.minCount;

  QuickPhraseState copyWith({
    required QuickPhraseStatus status,
    List<QuickPhrase>? phrases,
    Failure? failure,
  }) => QuickPhraseState(
    phrases: phrases ?? this.phrases,
    status: status,
    failure: failure,
  );

  @override
  List<Object?> get props => [phrases, status, failure];
}

class QuickPhraseBloc extends Bloc<QuickPhraseEvent, QuickPhraseState> {
  QuickPhraseBloc(this._repository)
    : super(QuickPhraseState(phrases: _repository.load())) {
    on<QuickPhraseUsed>((event, _) {
      unawaited(_repository.recordUse(event.phrase));
    });
    on<QuickPhraseAdded>(
      (event, emit) => _mutate(emit, () => _repository.add(event.text)),
      transformer: droppable(),
    );
    on<QuickPhraseRemoved>(
      (event, emit) => _mutate(emit, () => _repository.remove(event.id)),
      transformer: droppable(),
    );
  }

  final QuickPhraseRepository _repository;

  Future<void> _mutate(
    Emitter<QuickPhraseState> emit,
    Future<Result<List<QuickPhrase>>> Function() operation,
  ) async {
    emit(state.copyWith(status: QuickPhraseStatus.saving));
    final result = await operation();
    emit(switch (result) {
      Success(:final value) => state.copyWith(
        phrases: value,
        status: QuickPhraseStatus.saved,
      ),
      FailureResult(:final failure) => state.copyWith(
        status: QuickPhraseStatus.failure,
        failure: failure,
      ),
    });
  }
}
