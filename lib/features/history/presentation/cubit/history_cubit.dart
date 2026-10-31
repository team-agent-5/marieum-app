import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/domain/entities/history_entry.dart';
import 'package:marieum_app/features/history/domain/entities/history_range.dart';
import 'package:marieum_app/features/history/domain/repositories/history_repository.dart';
import 'package:marieum_app/features/history/domain/utils/history_date_range.dart';

enum HistoryStatus { initial, loading, success, failure }

class HistoryState extends Equatable {
  const HistoryState({
    this.range = HistoryRange.today,
    this.status = HistoryStatus.initial,
    this.entries = const [],
    this.nextCursor,
    this.total = 0,
    this.failure,
  });
  final HistoryRange range;
  final HistoryStatus status;
  final List<HistoryEntry> entries;
  final String? nextCursor;
  final int total;
  final Failure? failure;
  @override
  List<Object?> get props => [
    range,
    status,
    entries,
    nextCursor,
    total,
    failure,
  ];
}

class HistoryCubit extends Cubit<HistoryState> {
  HistoryCubit(this._repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const HistoryState());
  final HistoryRepository _repository;
  final DateTime Function() _now;
  int _revision = 0;
  String? _since;
  Future<void> load([HistoryRange? range]) async {
    final selected = range ?? state.range;
    final revision = ++_revision;
    final since = historySince(_now(), selected);
    _since = since;
    emit(HistoryState(range: selected, status: HistoryStatus.loading));
    final result = await _repository.page(since: since);
    if (isClosed || revision != _revision) return;
    emit(switch (result) {
      Success(:final value) => HistoryState(
        range: selected,
        status: HistoryStatus.success,
        entries: value.entries,
        nextCursor: value.nextCursor,
        total: value.total,
      ),
      FailureResult(:final failure) => HistoryState(
        range: selected,
        status: HistoryStatus.failure,
        failure: failure,
      ),
    });
  }

  Future<void> more() async {
    final previous = state;
    if (previous.status == HistoryStatus.loading ||
        previous.nextCursor == null ||
        _since == null) {
      return;
    }
    final revision = _revision;
    emit(
      HistoryState(
        range: previous.range,
        status: HistoryStatus.loading,
        entries: previous.entries,
        nextCursor: previous.nextCursor,
        total: previous.total,
      ),
    );
    final result = await _repository.page(
      since: _since!,
      cursor: previous.nextCursor,
    );
    if (isClosed || revision != _revision) return;
    switch (result) {
      case Success(:final value):
        final entries = {
          for (final entry in [...previous.entries, ...value.entries])
            entry.logId: entry,
        };
        emit(
          HistoryState(
            range: previous.range,
            status: HistoryStatus.success,
            entries: List.unmodifiable(entries.values),
            nextCursor: value.nextCursor,
            total: value.total,
          ),
        );
      case FailureResult(:final failure):
        emit(
          HistoryState(
            range: previous.range,
            status: HistoryStatus.failure,
            entries: previous.entries,
            nextCursor: previous.nextCursor,
            total: previous.total,
            failure: failure,
          ),
        );
    }
  }
}
