import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/domain/entities/history_page_data.dart';

// 원격 구현과 모의 구현을 같은 인터페이스로 교체한다.
// ignore: one_member_abstracts
abstract interface class HistoryDataSource {
  Future<Result<HistoryPageData>> page({
    required String? since,
    String? cursor,
  });
}
