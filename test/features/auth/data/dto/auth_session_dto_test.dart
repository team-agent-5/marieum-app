import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/auth/data/dto/auth_session_dto.dart';

void main() {
  group(AuthSessionDto, () {
    group('parseProfile', () {
      for (final (value, expected) in <(Object?, bool)>[
        (true, true),
        (false, false),
        ('true', true),
        ('false', false),
        (null, false),
      ]) {
        test('accepts onboarding value $value (${value.runtimeType})', () {
          final profile = AuthSessionDto.parseProfile({
            'id': 42,
            'nickname': '환자',
            'onboarding_completed': value,
          }, userId: 'demo_a');
          expect(profile.onboardingCompleted, expected);
          expect(profile.id, '42');
        });
      }
      for (final (nickname, displayName, expected)
          in <(Object?, Object?, String)>[
            ('환자', '표시 이름', '환자'),
            (null, '표시 이름', '표시 이름'),
            ('', '표시 이름', '표시 이름'),
            ('  ', '표시 이름', '표시 이름'),
            (null, null, 'demo_a'),
            ('', '', 'demo_a'),
            (null, '  ', 'demo_a'),
          ]) {
        test('uses nickname=$nickname then display_name=$displayName', () {
          final profile = AuthSessionDto.parseProfile({
            'id': 'patient-42',
            'nickname': nickname,
            'display_name': displayName,
          }, userId: 'demo_a');
          expect(profile.nickname, expected);
          expect(profile.userId, 'demo_a');
          expect(profile.onboardingCompleted, isFalse);
          expect(profile.id, 'patient-42');
        });
      }
      for (final id in <Object?>[null, true, 1.5]) {
        test('still rejects patient ID $id (${id.runtimeType})', () {
          expect(
            () => AuthSessionDto.parseProfile({'id': id}, userId: 'demo_a'),
            throwsFormatException,
          );
        });
      }
    });
    group('fromJson', () {
      test('uses the same defaults for a sparse signup or login patient', () {
        final session = AuthSessionDto.fromJson({
          'access_token': 'token',
          'patient': {'id': 42},
        }, userId: 'demo_a');
        expect(session.profile.nickname, 'demo_a');
        expect(session.profile.onboardingCompleted, isFalse);
      });
    });
  });
}
