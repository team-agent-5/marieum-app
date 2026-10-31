import 'package:equatable/equatable.dart';
import 'package:marieum_app/core/error/result.dart';

enum HistoryRange { today, week }

class HistoryEntry extends Equatable {
  const HistoryEntry({
    required this.logId,
    required this.text,
    required this.source,
    required this.createdAt,
    this.selectedRank,
  });
  final String logId;
  final String text;
  final String source;
  final DateTime createdAt;
  final int? selectedRank;
  @override
  List<Object?> get props => [logId, text, source, createdAt, selectedRank];
}

class HistoryPageData {
  const HistoryPageData({
    required this.entries,
    required this.total,
    this.nextCursor,
  });
  final List<HistoryEntry> entries;
  final int total;
  final String? nextCursor;
}

abstract interface class HistoryRepository {
  Future<Result<List<HistoryEntry>>> recent();
  Future<Result<HistoryPageData>> page({required String since, String? cursor});
  Future<Result<List<HistoryEntry>>> all({required String since});
}

String localMidnightIso(DateTime now, {int daysAgo = 0}) {
  final local = now.toLocal();
  final midnight = DateTime(local.year, local.month, local.day - daysAgo);
  final offset = midnight.timeZoneOffset;
  final minutes = offset.inMinutes.abs();
  final sign = offset.isNegative ? '-' : '+';
  final hours = (minutes ~/ 60).toString().padLeft(2, '0');
  final remainder = (minutes % 60).toString().padLeft(2, '0');
  return '${midnight.toIso8601String()}$sign$hours:$remainder';
}

String historySince(DateTime now, HistoryRange range) =>
    localMidnightIso(now, daysAgo: range == HistoryRange.week ? 6 : 0);
