import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/domain/entities/history_entry.dart';
import 'package:marieum_app/features/history/domain/entities/history_page_data.dart';

abstract interface class HistoryRepository {
  Future<Result<List<HistoryEntry>>> recent();
  Future<Result<HistoryPageData>> page({required String since, String? cursor});
  Future<Result<List<HistoryEntry>>> all({required String since});
}
