// Domain values stay independent of Flutter and annotation packages.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

class PatientProfile {
  const PatientProfile({
    required this.id,
    required this.nickname,
    required this.onboardingCompleted,
    required this.userId,
  });
  final String id;
  final String nickname;
  final bool onboardingCompleted;
  final String userId;
  PatientProfile onboarded() => PatientProfile(
    id: id,
    nickname: nickname,
    onboardingCompleted: true,
    userId: userId,
  );
  @override
  bool operator ==(Object other) =>
      other is PatientProfile &&
      id == other.id &&
      nickname == other.nickname &&
      onboardingCompleted == other.onboardingCompleted &&
      userId == other.userId;
  @override
  int get hashCode => Object.hash(id, nickname, onboardingCompleted, userId);
}
