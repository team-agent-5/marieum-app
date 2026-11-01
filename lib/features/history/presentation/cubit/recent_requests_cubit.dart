import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/domain/entities/history_entry.dart';
import 'package:marieum_app/features/history/domain/repositories/history_repository.dart';

class RecentRequestsState extends Equatable {
  const RecentRequestsState({
    this.entries = const [],
    this.loading = false,
    this.failure,
  });
  final List<HistoryEntry> entries;
  final bool loading;
  final Failure? failure;
  @override
  List<Object?> get props => [entries, loading, failure];
}

class RecentRequestsCubit extends Cubit<RecentRequestsState> {
  RecentRequestsCubit(this._repository) : super(const RecentRequestsState());
  final HistoryRepository _repository;
  Future<void> load() async {
    if (state.loading) return;
    emit(const RecentRequestsState(loading: true));
    final result = await _repository.recent();
    if (isClosed) return;
    emit(switch (result) {
      Success(:final value) => RecentRequestsState(entries: value),
      FailureResult(:final failure) => RecentRequestsState(failure: failure),
    });
  }
}
