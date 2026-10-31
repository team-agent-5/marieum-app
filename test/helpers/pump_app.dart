import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/marieum_app.dart';
import 'package:marieum_app/app/router/app_router.dart';
import 'package:marieum_app/app/router/auth_router_refresh.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/domain/entities/patient_profile.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}

class _MockAuthRepository extends Mock implements AuthRepository {}

const testProfile = PatientProfile(
  id: '1',
  nickname: '김환자',
  onboardingCompleted: true,
  userId: 'demo_a',
);

extension PumpApp on WidgetTester {
  Future<GoRouter> pumpApp({
    String initialLocation = '/speak',
    AuthBloc? authBloc,
    AuthRepository? repository,
    AuthStatus status = const AuthAuthenticated(testProfile),
    bool settle = true,
  }) async {
    final bloc = authBloc ?? _MockAuthBloc();
    if (authBloc == null) {
      when(() => bloc.state).thenReturn(AuthState(status));
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
    }
    final authRepository = repository ?? _MockAuthRepository();
    if (repository == null) {
      when(authRepository.restore).thenAnswer((_) async => const Success(null));
    }
    final refresh = AuthRouterRefresh(bloc);
    addTearDown(refresh.dispose);
    final router = createAppRouter(
      initialLocation: initialLocation,
      authBloc: bloc,
      repository: authRepository,
      refresh: refresh,
    );
    await pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: MarieumApp(
          router: router,
        ),
      ),
    );
    if (settle) {
      await pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
    } else {
      await pump();
    }
    return router;
  }
}
