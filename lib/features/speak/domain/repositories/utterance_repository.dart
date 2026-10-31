import 'package:marieum_app/core/audio/recorded_audio.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';

abstract interface class UtteranceRepository {
  Future<Result<Transcription>> transcribe(RecordedAudio audio);
  Future<Result<Suggestions>> suggest(Transcription transcription);

  /// Live mode: logs the transcript and returns the sentence to speak.
  Future<Result<String>> bypass(
    Transcription transcription, {
    required Duration latency,
  });

  /// Selection and rejection logs feed ranking. They are queued and sent in
  /// the background so playback never waits on them.
  void logSelected({
    required Transcription transcription,
    required Suggestions suggestions,
    required Candidate candidate,
    required Duration latency,
  });

  void logRejected({
    required Transcription transcription,
    required Suggestions suggestions,
    required Duration latency,
  });
}
