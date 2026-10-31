// Domain values stay independent of Flutter and annotation packages.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/features/auth/domain/entities/patient_profile.dart';

sealed class AuthStatus {
  const AuthStatus();
}

final class AuthUnknown extends AuthStatus {
  const AuthUnknown({this.failure});
  final Failure? failure;
  @override
  bool operator ==(Object other) =>
      other is AuthUnknown && failure == other.failure;
  @override
  int get hashCode => Object.hash(AuthUnknown, failure);
}

final class AuthUnauthenticated extends AuthStatus {
  const AuthUnauthenticated();
  @override
  bool operator ==(Object other) => other is AuthUnauthenticated;
  @override
  int get hashCode => runtimeType.hashCode;
}

final class AuthAuthenticated extends AuthStatus {
  const AuthAuthenticated(this.profile);
  final PatientProfile profile;
  @override
  bool operator ==(Object other) =>
      other is AuthAuthenticated && profile == other.profile;
  @override
  int get hashCode => Object.hash(AuthAuthenticated, profile);
}
