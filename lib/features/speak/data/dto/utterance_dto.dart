import 'package:marieum_app/features/speak/domain/entities/utterance.dart';

abstract final class UtteranceDto {
  static Transcription transcription(Object? json) {
    final body = _map(json);
    return Transcription(
      traceId: _string(body['trace_id']),
      finalTranscript: (body['final_transcript'] as String?) ?? '',
      asrConfidence: _number(body['asr_confidence']),
      heardText: _nonBlank(body['heard_text']),
    );
  }

  static Suggestions suggestions(Object? json) {
    final body = _map(json);
    final raw = body['candidates'];
    final candidates = <Candidate>[
      if (raw is List)
        for (final item in raw)
          if (item is Map) _candidate(Map<String, Object?>.from(item)),
    ]..sort((a, b) => a.rank.compareTo(b.rank));
    return Suggestions(
      traceId: _string(body['trace_id']),
      candidates: candidates.take(3).toList(growable: false),
      fallbackHint: _nonBlank(body['fallback_hint']),
    );
  }

  static String logId(Object? json) => _string(_map(json)['log_id']);

  static ({String logId, String finalText}) spoken(Object? json) {
    final body = _map(json);
    final text = _nonBlank(body['final_text']);
    if (text == null) throw const FormatException('Missing final_text.');
    return (logId: _string(body['log_id']), finalText: text);
  }

  static Map<String, Object?> candidateSnapshot(
    Candidate candidate, {
    required String fallbackSource,
  }) => {
    'rank': candidate.rank,
    'text': candidate.text,
    'score': candidate.score.clamp(0, 1),
    'reason_label': candidate.reasonLabel,
    'source': switch (candidate.source) {
      CandidateSource.catalog => 'catalog',
      CandidateSource.patientLog => 'patient_log',
      CandidateSource.llmGen => 'llm_gen',
      null => fallbackSource,
    },
  };

  static Candidate _candidate(Map<String, Object?> json) => Candidate(
    rank: (json['rank']! as num).toInt(),
    text: json['text']! as String,
    score: _number(json['score']),
    reasonLabel: _nonBlank(json['reason_label']),
    reasonDisplay: _nonBlank(json['reason_display']),
    source: switch (json['source']) {
      'catalog' => CandidateSource.catalog,
      'patient_log' => CandidateSource.patientLog,
      'llm_gen' => CandidateSource.llmGen,
      _ => null,
    },
  );

  static Map<String, Object?> _map(Object? json) =>
      Map<String, Object?>.from(json! as Map);

  static String _string(Object? value) => switch (value) {
    final String text when text.isNotEmpty => text,
    final num number => number.toString(),
    _ => throw const FormatException('Missing identifier.'),
  };

  static double _number(Object? value) => switch (value) {
    final num number => number.toDouble(),
    final String text => double.parse(text),
    _ => 0,
  };

  static String? _nonBlank(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;
}
