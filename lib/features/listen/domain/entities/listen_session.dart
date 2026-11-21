import 'package:equatable/equatable.dart';

/// Where the patient's listening session stands, as the server reports it.
enum ListenStatus { waiting, connected, ended }

/// A listening session the patient opened; the other phone joins it with
/// [joinCode] until [joinExpiresAt], and it ends by [expiresAt] at the latest.
class ListenSession extends Equatable {
  const ListenSession({
    required this.id,
    required this.joinCode,
    required this.joinExpiresAt,
    required this.expiresAt,
  });

  final String id;
  final String joinCode;
  final DateTime joinExpiresAt;
  final DateTime expiresAt;

  @override
  List<Object?> get props => [id, joinCode, joinExpiresAt, expiresAt];
}

/// What the other phone gets for joining: a token for `/ws/listen` only.
class ListenerPass extends Equatable {
  const ListenerPass({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;

  @override
  List<Object?> get props => [token, expiresAt];
}

/// Why the other phone stopped hearing the patient.
enum ListenEndReason {
  /// The patient ended the session.
  patientLeft,

  /// The session ran past its two hours, or the server no longer has it.
  expired,

  /// The patient started a new session, which replaced this one.
  revoked,

  /// The token was refused.
  tokenInvalid,

  /// Another phone is already connected with this session.
  otherDevice,

  /// The server could not be reached again in time.
  connectionLost,
}

/// The six-character code that joins a session: upper case letters and
/// digits without 0, O, 1 and I, so it reads back without confusion.
abstract final class JoinCode {
  static const length = 6;
  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// What the patient's QR code holds.
  static const _scheme = 'marieum:listen:';

  /// Upper-cased with spaces and dashes removed, or null when it is not a
  /// code.
  static String? normalize(String raw) {
    final code = raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (code.length != length) return null;
    for (final char in code.split('')) {
      if (!alphabet.contains(char)) return null;
    }
    return code;
  }

  /// The QR payload for [code].
  static String qrPayload(String code) => '$_scheme$code';

  /// The code in a scanned QR payload, or null when the QR is not a
  /// Marieum listening code.
  static String? fromScan(String payload) {
    final text = payload.trim();
    if (!text.startsWith(_scheme)) return null;
    return normalize(text.substring(_scheme.length));
  }
}
