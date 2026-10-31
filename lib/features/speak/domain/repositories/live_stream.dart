import 'dart:typed_data';

import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';

sealed class LiveEvent {
  const LiveEvent();
}

/// What the server understands so far; replaced by later events.
final class LiveInterim extends LiveEvent {
  const LiveInterim(this.text);
  final String text;
}

final class LiveFinal extends LiveEvent {
  const LiveFinal(this.transcription);
  final Transcription transcription;
}

/// The server could not make out the speech.
final class LiveUnclear extends LiveEvent {
  const LiveUnclear();
}

final class LiveFailed extends LiveEvent {
  const LiveFailed(this.failure);
  final Failure failure;
}

/// One utterance streamed to the server while the patient speaks. [events]
/// ends after a single [LiveFinal], [LiveUnclear] or [LiveFailed], or
/// without one when cancelled.
abstract interface class LiveUtterance {
  Stream<LiveEvent> get events;

  /// PCM16 16 kHz mono audio.
  void add(Uint8List audio);

  /// The patient paused; asks for the final transcript.
  void end();
  void cancel();
}

// A named boundary keeps the transport swappable and mockable.
// ignore: one_member_abstracts
abstract interface class LiveStream {
  LiveUtterance open();
}
