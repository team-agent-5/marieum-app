import 'package:equatable/equatable.dart';

/// Below this ASR confidence the patient is asked to speak again.
/// Pending a final value from the backend team; the server currently
/// enforces the same bound on `/phrase/bypass`.
const lowConfidenceThreshold = 0.4;

class Transcription extends Equatable {
  const Transcription({
    required this.traceId,
    required this.finalTranscript,
    required this.asrConfidence,
    this.heardText,
  });

  final String traceId;
  final String finalTranscript;
  final double asrConfidence;
  final String? heardText;

  bool get isLowConfidence =>
      asrConfidence < lowConfidenceThreshold || finalTranscript.trim().isEmpty;

  /// What the patient sees under "들린 내용".
  String get heard => heardText ?? finalTranscript;

  @override
  List<Object?> get props => [
    traceId,
    finalTranscript,
    asrConfidence,
    heardText,
  ];
}

enum CandidateSource {
  catalog,
  patientLog,
  llmGen,
  asrVerbatim,
  llmInference,
  llmReconstruction,
}

enum SuggestionMode { proactive, candidates, single, retry }

class Candidate extends Equatable {
  const Candidate({
    required this.rank,
    required this.text,
    required this.score,
    this.reasonLabel,
    this.reasonDisplay,
    this.source,
  });

  final int rank;
  final String text;
  final double score;
  final String? reasonLabel;
  final String? reasonDisplay;
  final CandidateSource? source;

  @override
  List<Object?> get props => [
    rank,
    text,
    score,
    reasonLabel,
    reasonDisplay,
    source,
  ];
}

class Suggestions extends Equatable {
  const Suggestions({
    required this.traceId,
    this.candidates = const [],
    this.mode = SuggestionMode.candidates,
    this.verbatim,
    this.proactiveSuggestion,
    this.retryMessage,
    this.branch,
    this.asrConfidence,
    this.coldStart = false,
    this.generatedAt,
    this.generationLatencyMs = 0,
  });

  final String traceId;
  final List<Candidate> candidates;
  final SuggestionMode mode;
  final Candidate? verbatim;
  final ProactiveSuggestion? proactiveSuggestion;
  final String? retryMessage;
  final String? branch;
  final double? asrConfidence;
  final bool coldStart;
  final DateTime? generatedAt;
  final int generationLatencyMs;

  bool get isEmpty => candidates.isEmpty;

  @override
  List<Object?> get props => [
    traceId,
    candidates,
    mode,
    verbatim,
    proactiveSuggestion,
    retryMessage,
    branch,
    asrConfidence,
    coldStart,
    generatedAt,
    generationLatencyMs,
  ];
}

class ProactiveSuggestion extends Equatable {
  const ProactiveSuggestion({required this.candidate, required this.modalText});
  final Candidate candidate;
  final String modalText;
  @override
  List<Object?> get props => [candidate, modalText];
}
