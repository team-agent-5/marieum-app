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

/// Whether the other phone is listening, sent once the connection opens and
/// whenever it changes.
enum ListenerPresence { joined, left, none }

final class LiveListener extends LiveEvent {
  const LiveListener(this.presence);
  final ListenerPresence presence;
}

/// The server's answer to one `say`: whether the other phone got it. When
/// it did not, this phone reads the sentence itself.
final class LiveSaid extends LiveEvent {
  const LiveSaid(this.utteranceId, {required this.delivered});
  final String utteranceId;
  final bool delivered;
}

/// The other phone finished saying a sentence aloud.
final class LivePlayed extends LiveEvent {
  const LivePlayed(this.utteranceId);
  final String utteranceId;
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

  /// Asks the server to have the other phone say [text]; a [LiveSaid] with
  /// the same id answers. False when it could not go out because the
  /// connection is not open, and no answer will come.
  bool say({
    required String utteranceId,
    required String text,
    required String traceId,
  });
  Future<void> close();
}

// A named boundary keeps the transport swappable and mockable.
// ignore: one_member_abstracts
abstract interface class LiveStream {
  LiveConversation connect();
}
