import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/network/api_client.dart';
import 'package:marieum_app/features/history/data/datasources/history_data_source.dart';
import 'package:marieum_app/features/history/data/dto/history_page_dto.dart';
import 'package:marieum_app/features/history/domain/entities/history_page_data.dart';

class RemoteHistoryDataSource implements HistoryDataSource {
  RemoteHistoryDataSource(this._client);
  final ApiClient _client;
  @override
  Future<Result<HistoryPageData>> page({
    required String? since,
    String? cursor,
  }) => _client.request(
    '/phrase/history',
    query: {
      'limit': 20,
      'since': ?since,
      'cursor': cursor ?? '',
    },
    decode: decodeHistoryPage,
  );
}
