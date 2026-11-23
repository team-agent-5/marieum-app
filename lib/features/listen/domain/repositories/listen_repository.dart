import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';

/// The patient's side: `/listen/sessions` with the patient's login.
abstract interface class ListenHostRepository {
  /// Opens a session; one the patient already had is ended.
  Future<Result<ListenSession>> create();

  /// The patient's session; [ListenSnapshot.none] when there is none
  /// (`404 LISTEN_NO_SESSION`).
  Future<Result<ListenSnapshot>> current();

  /// Ends the session; the other phone is told.
  Future<Result<void>> end();
}

/// The other phone's side, without a login.
// Kept as an interface so remote and fake sources can be swapped.
// ignore: one_member_abstracts
abstract interface class ListenJoinRepository {
  /// Trades a join code for a listener token. Fails with `errorCode`
  /// `LISTEN_CODE_INVALID` (404), `LISTENER_ALREADY_JOINED` (409) or
  /// `RATE_LIMITED` (429).
  Future<Result<ListenerPass>> join(String code);
}
