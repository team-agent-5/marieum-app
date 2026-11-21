import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';

/// What comes to the other phone over `/ws/listen`.
sealed class ListenerEvent {
  const ListenerEvent();
}

/// Connected, at first or again after a drop.
final class ListenerConnected extends ListenerEvent {
  const ListenerConnected();
}

/// The connection dropped and is being opened again.
final class ListenerReconnecting extends ListenerEvent {
  const ListenerReconnecting();
}

/// A sentence the patient wants said aloud.
final class ListenerSay extends ListenerEvent {
  const ListenerSay({required this.utteranceId, required this.text});
  final String utteranceId;
  final String text;
}

/// The session is over; nothing more comes and the connection is closed.
final class ListenerEnded extends ListenerEvent {
  const ListenerEnded(this.reason);
  final ListenEndReason reason;
}

// Kept as an interface so the socket and test fakes can be swapped.
// ignore: one_member_abstracts
abstract interface class ListenerChannel {
  /// Connects with [pass] and keeps reconnecting after drops until the
  /// session ends or the connection is closed.
  ListenerConnection connect(ListenerPass pass);
}

abstract interface class ListenerConnection {
  Stream<ListenerEvent> get events;

  /// Tells the patient's phone [utteranceId] was said aloud.
  void played(String utteranceId);

  Future<void> close();
}
