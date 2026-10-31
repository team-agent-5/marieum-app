import 'package:marieum_app/features/speak/domain/entities/utterance.dart';

enum PlaybackOrigin { utterance, quickPhrase, history, preview }

class PlaybackRequest {
  const PlaybackRequest({
    required this.text,
    required this.origin,
    this.phraseLogId,
    this.suggestions,
    this.transcription,
  });

  final String text;
  final PlaybackOrigin origin;
  final String? phraseLogId;
  final Suggestions? suggestions;
  final Transcription? transcription;
}
