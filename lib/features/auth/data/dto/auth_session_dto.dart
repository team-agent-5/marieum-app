import 'package:marieum_app/features/auth/domain/entities/patient_profile.dart';

class AuthSessionDto {
  const AuthSessionDto({required this.accessToken, required this.profile});
  factory AuthSessionDto.fromJson(Object? json, {required String userId}) {
    final body = json! as Map<String, Object?>;
    final token = body['access_token']! as String;
    if (token.isEmpty) throw const FormatException('Empty access token.');
    return AuthSessionDto(
      accessToken: token,
      profile: parseProfile(body['patient'], userId: userId),
    );
  }
  final String accessToken;
  final PatientProfile profile;
  static bool parseOnboardingCompleted(Object? value) => switch (value) {
    final bool completed => completed,
    'true' => true,
    'false' || null => false,
    _ => throw const FormatException('Invalid onboarding completion value.'),
  };

  static String? _nonBlank(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static PatientProfile parseProfile(Object? json, {required String userId}) {
    final body = json! as Map<String, Object?>;
    final id = body['id'];
    if (id is! String && id is! int) {
      throw const FormatException('Invalid patient ID.');
    }
    return PatientProfile(
      id: id.toString(),
      nickname:
          _nonBlank(body['nickname']) ??
          _nonBlank(body['display_name']) ??
          userId,
      onboardingCompleted: parseOnboardingCompleted(
        body['onboarding_completed'],
      ),
      userId: userId,
    );
  }
}
