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
    final mode = switch (body['mode']) {
      'proactive' => SuggestionMode.proactive,
      'single' => SuggestionMode.single,
      'retry' => SuggestionMode.retry,
      'candidates' || null => SuggestionMode.candidates,
      _ => throw const FormatException('Unknown suggestion mode.'),
    };
    Candidate? verbatim;
    ProactiveSuggestion? proactive;
    final candidates = <Candidate>[];
    switch (mode) {
      case SuggestionMode.proactive:
        final raw = _map(body['verbatim']);
        verbatim = _candidate({
          ...raw,
          'rank': 1,
          'score': body['asr_confidence'],
        });
        candidates.add(verbatim);
        if (body['suggestion'] != null) {
          final suggestion = _map(body['suggestion']);
          final candidate = _candidate({
            'rank': 2,
            'text': suggestion['phrase'],
            'score': suggestion['confidence'],
            'reason_display': suggestion['reason_display'],
            'source': 'llm_inference',
          });
          proactive = ProactiveSuggestion(
            candidate: candidate,
            modalText: _requiredText(suggestion['modal_text']),
          );
          candidates.add(candidate);
        }
      case SuggestionMode.candidates:
        final raw = body['candidates'];
        if (raw is! List) throw const FormatException('Missing candidates.');
        candidates.addAll(raw.map((item) => _candidate(_map(item))));
        candidates.sort((a, b) => a.rank.compareTo(b.rank));
      case SuggestionMode.single:
        candidates.add(_candidate(_map(body['candidate'])));
      case SuggestionMode.retry:
        _requiredText(body['message']);
    }
    return Suggestions(
      traceId: _string(body['trace_id']),
      candidates: candidates.take(3).toList(growable: false),
      mode: mode,
      verbatim: verbatim,
      proactiveSuggestion: proactive,
      retryMessage: _nonBlank(body['message']),
      branch: _nonBlank(body['branch']),
      asrConfidence: body['asr_confidence'] == null
          ? null
          : _number(body['asr_confidence']),
      coldStart: body['cold_start'] == true,
      generatedAt: DateTime.tryParse(body['generated_at']?.toString() ?? ''),
      generationLatencyMs: _number(body['generation_latency_ms']).toInt(),
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
      CandidateSource.asrVerbatim => 'asr_verbatim',
      CandidateSource.llmInference => 'llm_inference',
      CandidateSource.llmReconstruction => 'llm_reconstruction',
      CandidateSource.catalogFallback => 'catalog_fallback',
      CandidateSource.rankerFallback => 'ranker_fallback',
      null => fallbackSource,
    },
  };

  static Candidate _candidate(Map<String, Object?> json) => Candidate(
    rank: (json['rank']! as num).toInt(),
    text: _requiredText(json['text']),
    score: _number(json['score']),
    reasonLabel: _nonBlank(json['reason_label']),
    reasonDisplay: _nonBlank(json['reason_display']),
    source: switch (json['source']) {
      'catalog' => CandidateSource.catalog,
      'patient_log' => CandidateSource.patientLog,
      'llm_gen' => CandidateSource.llmGen,
      'asr_verbatim' => CandidateSource.asrVerbatim,
      'llm_inference' => CandidateSource.llmInference,
      'llm_reconstruction' => CandidateSource.llmReconstruction,
      'catalog_fallback' => CandidateSource.catalogFallback,
      'ranker_fallback' => CandidateSource.rankerFallback,
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

  static String _requiredText(Object? value) =>
      _nonBlank(value) ?? (throw const FormatException('Missing text.'));
}
