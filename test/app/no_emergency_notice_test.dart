import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/domain/entities/patient_profile.dart';

import '../helpers/pump_app.dart';

void main() {
  const notOnboarded = AuthAuthenticated(
    PatientProfile(
      id: '1',
      nickname: '김환자',
      onboardingCompleted: false,
      userId: 'demo_b',
    ),
  );

  final screens = <String, (String, AuthStatus)>{
    'signup': ('/signup', const AuthUnauthenticated()),
    'login': ('/login', const AuthUnauthenticated()),
    'onboarding': ('/onboarding', notOnboarded),
    'main': ('/speak', const AuthAuthenticated(testProfile)),
    'settings': ('/settings', const AuthAuthenticated(testProfile)),
  };

  group('emergency notice', () {
    for (final MapEntry(key: name, value: (location, status))
        in screens.entries) {
      testWidgets('is not shown on $name', (tester) async {
        final router = await tester.pumpApp(
          initialLocation: location,
          status: status,
        );
        addTearDown(router.dispose);

        expect(router.state.uri.path, location);
        for (final text in ['119', '응급', '호출벨']) {
          expect(
            find.textContaining(text, findRichText: true),
            findsNothing,
          );
        }
      });
    }
  });
}
