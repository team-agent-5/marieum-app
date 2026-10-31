import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/features/auth/data/datasources/mock_auth_data_source.dart';
import 'package:marieum_app/features/auth/data/dto/auth_session_dto.dart';
import 'package:marieum_app/features/auth/domain/entities/patient_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group(MockAuthDataSource, () {
    late PrefsStore prefs;
    late MockAuthDataSource source;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = PrefsStore(
        SharedPrefsBackend(await SharedPreferences.getInstance()),
      );
      source = MockAuthDataSource(prefs);
    });
    test(
      'accepts arbitrary credentials and marks only demo_a '
      'onboarded by default',
      () async {
        final returning =
            await source.login(userId: 'demo_a', password: '')
                as Success<AuthSessionDto>;
        final fresh =
            await source.login(userId: 'other', password: 'any')
                as Success<AuthSessionDto>;
        expect(returning.value.profile.onboardingCompleted, isTrue);
        expect(fresh.value.profile.onboardingCompleted, isFalse);
      },
    );
    test(
      'persists completed mock onboarding and keeps separate account profiles',
      () async {
        final created =
            await source.signup(
                  userId: 'user_1',
                  password: '',
                  passwordConfirm: '',
                  nickname: '환자',
                )
                as Success<AuthSessionDto>;
        await source.markOnboarded(created.value.profile);
        final restarted = MockAuthDataSource(prefs);
        final restored =
            await restarted.profile(
                  userId: 'user_1',
                  token: created.value.accessToken,
                )
                as Success<PatientProfile>;
        expect(restored.value.nickname, '환자');
        expect(restored.value.onboardingCompleted, isTrue);
        final other =
            await restarted.login(userId: 'user_2', password: '')
                as Success<AuthSessionDto>;
        expect(other.value.profile.onboardingCompleted, isFalse);
      },
    );
  });
}
