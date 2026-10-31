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

/// Offline stand-in used with `USE_MOCK`. Recordings shorter than one second
/// come back with low confidence so the re-ask flow can be exercised.
class MockUtteranceDataSource implements UtteranceDataSource {
  static const _lowConfidenceBelow = Duration(seconds: 1);
  final _recent = <String>[];
  var _sequence = 0;

  @override
  Future<Result<Transcription>> transcribe(RecordedAudio audio) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final unclear = audio.durationMs < _lowConfidenceBelow.inMilliseconds;
    return Success(
      Transcription(
        traceId: 'mock-${++_sequence}',
        finalTranscript: unclear ? '무ㅏ 조세여' : '물 좀 주세요',
        asrConfidence: unclear ? 0.22 : 0.82,
        heardText: unclear ? '무ㅏ 조세여' : null,
      ),
    );
  }

  @override
  Future<Result<Suggestions>> suggest(Map<String, Object?> body) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    const base = [
      ('물 주세요', 'patient_frequency', '자주 쓰는 말'),
      ('미지근한 물 주세요', 'time_context', '이 시간대에 자주 선택'),
      ('물 말고 차 주세요', 'cold_start', null),
    ];
    final ordered = [
      for (final text in _recent.reversed)
        if (base.any((item) => item.$1 == text))
          base.firstWhere((item) => item.$1 == text),
      for (final item in base)
        if (!_recent.contains(item.$1)) item,
    ];
    return Success(
      Suggestions(
        traceId: body['trace_id']! as String,
        candidates: [
          for (final (index, item) in ordered.indexed)
            Candidate(
              rank: index + 1,
              text: item.$1,
              score: 0.9 - index * 0.15,
              reasonLabel: _recent.contains(item.$1) ? 'recency' : item.$2,
              reasonDisplay: _recent.contains(item.$1) ? '최근 요청' : item.$3,
              source: CandidateSource.catalog,
            ),
        ],
      ),
    );
  }

  @override
  Future<Result<String>> selection(Map<String, Object?> body) async {
    final phrase = body['selected_phrase'] as String?;
    if (phrase != null) {
      _recent
        ..remove(phrase)
        ..add(phrase);
    }
    return Success('${++_sequence}');
  }

  @override
  Future<Result<({String logId, String finalText})>> bypass(
    Map<String, Object?> body,
  ) async => Success((
    logId: '${++_sequence}',
    finalText: body['final_transcript']! as String,
  ));
}
