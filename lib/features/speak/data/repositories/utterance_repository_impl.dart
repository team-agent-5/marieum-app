import 'dart:async';

import 'package:marieum_app/core/audio/recorded_audio.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/storage/sequence_store.dart';
import 'package:marieum_app/features/speak/data/datasources/selection_log_queue.dart';
import 'package:marieum_app/features/speak/data/datasources/utterance_data_source.dart';
import 'package:marieum_app/features/speak/data/dto/utterance_dto.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:marieum_app/features/speak/domain/repositories/utterance_repository.dart';

class UtteranceRepositoryImpl implements UtteranceRepository {
  UtteranceRepositoryImpl({
    required this._source,
    required this._queue,
    required this._sequence,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    unawaited(_queue.flush());
  }

  /// `/phrase/suggest` candidates do not carry the generation source that
  /// `CandidateSnapshot.source` requires; this value fills the gap until the
  /// backend exposes it.
  static const fallbackCandidateSource = 'catalog';

  final UtteranceDataSource _source;
  final SelectionLogQueue _queue;
  final SequenceStore _sequence;
  final DateTime Function() _now;

  int? get _previousLogId => int.tryParse(_sequence.lastLogId ?? '');

  @override
  Future<Result<Transcription>> transcribe(RecordedAudio audio) =>
      _source.transcribe(audio);

  @override
  Future<Result<Suggestions>> suggest(Transcription transcription) =>
      _source.suggest({
        'patient_prefix': _clip(transcription.finalTranscript, 200),
        'final_transcript': _clip(transcription.finalTranscript, 400),
        'asr_confidence': transcription.asrConfidence.clamp(0, 1),
        'source': 'voice',
        'trace_id': transcription.traceId,
        'previous_log_id': _previousLogId,
        'client_ts': _isoWithOffset(_now()),
      });

  @override
  Future<Result<String>> bypass(
    Transcription transcription, {
    required Duration latency,
  }) async {
    final result = await _source.bypass({
      'final_transcript': _clip(transcription.finalTranscript, 400),
      'asr_confidence': transcription.asrConfidence.clamp(0, 1),
      'trace_id': transcription.traceId,
      'latency_ms': latency.inMilliseconds,
    });
    switch (result) {
      case Success(:final value):
        try {
          await _sequence.save(value.logId);
        } on Object {
          // The sentence is still spoken when the sequence hint cannot be kept.
        }
        return Success(value.finalText);
      case FailureResult(:final failure):
        return FailureResult<String>(failure);
    }
  }

  @override
  void logSelected({
    required Transcription transcription,
    required Suggestions suggestions,
    required Candidate candidate,
    required Duration latency,
  }) => unawaited(
    _queue.enqueue({
      ..._logBase(transcription, suggestions, latency),
      'action': 'selected',
      'selected_phrase': candidate.text,
      'selected_rank': candidate.rank,
    }),
  );

  @override
  void logRejected({
    required Transcription transcription,
    required Suggestions suggestions,
    required Duration latency,
  }) {
    if (suggestions.candidates.isEmpty) return;
    unawaited(
      _queue.enqueue({
        ..._logBase(transcription, suggestions, latency),
        'action': 'rejected',
        'selected_phrase': null,
        'selected_rank': null,
        'reject_reason': 'not_this_phrase',
      }),
    );
  }

  Map<String, Object?> _logBase(
    Transcription transcription,
    Suggestions suggestions,
    Duration latency,
  ) => {
    'trace_id': suggestions.traceId,
    'prefix': _clip(transcription.finalTranscript, 200),
    'final_transcript': _clip(transcription.finalTranscript, 400),
    'candidates_shown': [
      for (final candidate in suggestions.candidates)
        UtteranceDto.candidateSnapshot(
          candidate,
          fallbackSource: fallbackCandidateSource,
        ),
    ],
    'latency_ms': latency.inMilliseconds,
    'source': 'voice',
    'prev_log_id': _previousLogId,
  };

  static String _clip(String text, int max) {
    final value = text.trim();
    final runes = value.runes;
    return runes.length <= max ? value : String.fromCharCodes(runes.take(max));
  }

  static String _isoWithOffset(DateTime time) {
    final offset = time.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    String two(int value) => value.abs().toString().padLeft(2, '0');
    final local = time.toIso8601String().split('.').first;
    return '$local$sign${two(offset.inHours)}:${two(offset.inMinutes % 60)}';
  }
}
