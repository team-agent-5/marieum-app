enum PlaybackOrigin { utterance, quickPhrase, history, preview }

class PlaybackRequest {
  const PlaybackRequest({
    required this.text,
    required this.origin,
    this.phraseLogId,
  });

  final String text;
  final PlaybackOrigin origin;
  final String? phraseLogId;
}
