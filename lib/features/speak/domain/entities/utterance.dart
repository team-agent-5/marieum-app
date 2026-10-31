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

enum CandidateSource { catalog, patientLog, llmGen }

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
    required this.candidates,
    this.fallbackHint,
  });

  final String traceId;
  final List<Candidate> candidates;
  final String? fallbackHint;

  bool get isEmpty => candidates.isEmpty || fallbackHint != null;

  @override
  List<Object?> get props => [traceId, candidates, fallbackHint];
}
