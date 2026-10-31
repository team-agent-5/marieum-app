import 'package:marieum_app/core/audio/recorded_audio.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/network/api_client.dart';
import 'package:marieum_app/features/speak/data/dto/utterance_dto.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';

abstract interface class UtteranceDataSource {
  Future<Result<Transcription>> transcribe(RecordedAudio audio);
  Future<Result<Suggestions>> suggest(Map<String, Object?> body);
  Future<Result<String>> selection(Map<String, Object?> body);
  Future<Result<({String logId, String finalText})>> bypass(
    Map<String, Object?> body,
  );
}

class RemoteUtteranceDataSource implements UtteranceDataSource {
  RemoteUtteranceDataSource(this._client);
  final ApiClient _client;

  @override
  Future<Result<Transcription>> transcribe(RecordedAudio audio) =>
      _client.uploadAudio(audio, decode: UtteranceDto.transcription);

  @override
  Future<Result<Suggestions>> suggest(Map<String, Object?> body) =>
      _client.request(
        '/phrase/suggest',
        method: 'POST',
        data: body,
        traceId: body['trace_id'] as String?,
        decode: UtteranceDto.suggestions,
      );

  @override
  Future<Result<String>> selection(Map<String, Object?> body) =>
      _client.request(
        '/phrase/selection',
        method: 'POST',
        data: body,
        traceId: body['trace_id'] as String?,
        decode: UtteranceDto.logId,
      );

  @override
  Future<Result<({String logId, String finalText})>> bypass(
    Map<String, Object?> body,
  ) => _client.request(
    '/phrase/bypass',
    method: 'POST',
    data: body,
    traceId: body['trace_id'] as String?,
    decode: UtteranceDto.spoken,
  );
}
