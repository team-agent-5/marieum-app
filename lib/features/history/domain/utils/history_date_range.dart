import 'package:marieum_app/features/history/domain/entities/history_range.dart';

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
