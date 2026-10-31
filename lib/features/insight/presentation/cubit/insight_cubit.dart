import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/domain/entities/history_range.dart';
import 'package:marieum_app/features/history/domain/repositories/history_repository.dart';
import 'package:marieum_app/features/history/domain/utils/history_date_range.dart';
import 'package:marieum_app/features/insight/domain/entities/insight_summary.dart';

enum InsightStatus { initial, loading, success, failure }

class InsightState extends Equatable {
  const InsightState({
    this.status = InsightStatus.initial,
    this.summary,
    this.failure,
  });
  final InsightStatus status;
  final InsightSummary? summary;
  final Failure? failure;
  @override
  List<Object?> get props => [status, summary, failure];
}

class InsightCubit extends Cubit<InsightState> {
  InsightCubit(this._repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const InsightState());
  final HistoryRepository _repository;
  final DateTime Function() _now;
  Future<void> load() async {
    if (state.status == InsightStatus.loading) return;
    emit(const InsightState(status: InsightStatus.loading));
    final result = await _repository.all(
      since: historySince(_now(), HistoryRange.week),
    );
    if (isClosed) return;
    emit(switch (result) {
      Success(:final value) => InsightState(
        status: InsightStatus.success,
        summary: InsightSummary.fromEntries(value),
      ),
      FailureResult(:final failure) => InsightState(
        status: InsightStatus.failure,
        failure: failure,
      ),
    });
  }
}
