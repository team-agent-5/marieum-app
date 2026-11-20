import 'dart:typed_data';

import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';

sealed class LiveEvent {
  const LiveEvent();
}

/// What the server understands so far of the sentence under way; replaced
/// by later events.
final class LiveInterim extends LiveEvent {
  const LiveInterim(this.text, {this.traceId = ''});
  final String text;

  /// The session's trace id, when the server sent one.
  final String traceId;
}

/// The server heard the patient finish a sentence.
final class LiveFinal extends LiveEvent {
  const LiveFinal(this.transcription);
  final Transcription transcription;
}

/// The server could not make out the sentence.
final class LiveUnclear extends LiveEvent {
  const LiveUnclear();
}

/// After the input was ended, the server has sent every sentence it had.
final class LiveSessionEnded extends LiveEvent {
  const LiveSessionEnded();
}

/// The connection is lost or refused; the conversation keeps trying unless
/// the failure is final, such as an expired login.
final class LiveFailed extends LiveEvent {
  const LiveFailed(this.failure, {this.recovering = true});
  final Failure failure;
  final bool recovering;
}

/// Live mode's one connection for the whole session: audio streams up
/// without pause and the server decides where each sentence ends.
abstract interface class LiveConversation {
  Stream<LiveEvent> get events;

  /// PCM16 16 kHz mono audio.
  void add(Uint8List audio);

  /// No more audio is coming: the server finishes the sentence it has and
  /// sends it as usual.
  void end();
  Future<void> close();
}

// A named boundary keeps the transport swappable and mockable.
// ignore: one_member_abstracts
abstract interface class LiveStream {
  LiveConversation connect();
}
