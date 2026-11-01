import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/network/session_expiry_signal.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/core/storage/secure_token_store.dart';
import 'package:marieum_app/core/storage/sequence_store.dart';
import 'package:marieum_app/features/auth/data/datasources/auth_data_source.dart';
import 'package:marieum_app/features/auth/data/dto/auth_session_dto.dart';
import 'package:marieum_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/domain/entities/patient_profile.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSource extends Mock implements AuthDataSource {}

class _MockTokens extends Mock implements SecureTokenStore {}

const _profile = PatientProfile(
  id: '42',
  nickname: '환자',
  onboardingCompleted: false,
  userId: 'user_1',
);
const _session = AuthSessionDto(accessToken: 'access-token', profile: _profile);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group(AuthRepositoryImpl, () {
    late _MockSource source;
    late _MockTokens tokens;
    late PrefsStore prefs;
    late SequenceStore sequence;
    late SessionExpirySignal expiry;
    late AuthRepositoryImpl repository;
    late String? storedToken;
    late List<AuthStatus> statuses;
    late StreamSubscription<AuthStatus> subscription;
    setUp(() async {
      SharedPreferences.setMockInitialValues({PrefsKeys.loginUserId: 'user_1'});
      prefs = PrefsStore(
        SharedPrefsBackend(await SharedPreferences.getInstance()),
      );
      sequence = SequenceStore(prefs);
      expiry = SessionExpirySignal();
      source = _MockSource();
      tokens = _MockTokens();
      storedToken = null;
      when(tokens.read).thenAnswer((_) async => storedToken);
      when(() => tokens.write(any())).thenAnswer((call) async {
        storedToken = call.positionalArguments.first as String;
      });
      when(tokens.clear).thenAnswer((_) async {
        storedToken = null;
      });
      when(
        () => source.profile(
          userId: 'user_1',
          token: any(named: 'token'),
        ),
      ).thenAnswer((_) async => const Success(_profile));
      when(
        () => source.login(userId: 'user_1', password: 'password'),
      ).thenAnswer((_) async => const Success(_session));
      when(
        () => source.signup(
          userId: 'user_1',
          password: 'password',
          passwordConfirm: 'password',
          nickname: '환자',
        ),
      ).thenAnswer((_) async => const Success(_session));
      when(source.logout).thenAnswer((_) async => const Success(null));
      when(
        () => source.markOnboarded(_profile),
      ).thenAnswer((_) async => const Success(null));
      repository = AuthRepositoryImpl(
        source: source,
        tokens: tokens,
        prefs: prefs,
        sequence: sequence,
        expiry: expiry,
      );
      statuses = [];
      subscription = repository.status.listen(statuses.add);
    });
    tearDown(() async {
      await subscription.cancel();
      await repository.dispose();
      await expiry.dispose();
    });
    test('replays current status to late subscribers', () async {
      await repository.restore();
      expect(await repository.status.first, const AuthUnauthenticated());
    });
    test(
      'restores without a token as unauthenticated and clears old sequence',
      () async {
        await sequence.save('old');
        await repository.restore();
        expect(repository.currentStatus, const AuthUnauthenticated());
        expect(sequence.lastLogId, isNull);
        verifyNever(
          () => source.profile(
            userId: any(named: 'userId'),
            token: any(named: 'token'),
          ),
        );
      },
    );
    test(
      'restores profile with persisted login ID '
      'because patient response has no user ID',
      () async {
        storedToken = 'existing';
        await repository.restore();
        expect(repository.currentStatus, const AuthAuthenticated(_profile));
        expect(storedToken, 'existing');
        verify(
          () => source.profile(userId: 'user_1', token: 'existing'),
        ).called(1);
      },
    );
    test(
      'retains token on network failure and permits successful restore retry',
      () async {
        storedToken = 'existing';
        when(
          () => source.profile(userId: 'user_1', token: 'existing'),
        ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
        expect(await repository.restore(), isA<FailureResult<void>>());
        expect(
          (repository.currentStatus as AuthUnknown).failure,
          isA<NetworkFailure>(),
        );
        expect(storedToken, 'existing');
        when(
          () => source.profile(userId: 'user_1', token: 'existing'),
        ).thenAnswer((_) async => const Success(_profile));
        await repository.restore();
        expect(repository.currentStatus, const AuthAuthenticated(_profile));
      },
    );
    test('expires invalid restored token and clears sequence', () async {
      storedToken = 'expired';
      await sequence.save('old');
      when(
        () => source.profile(userId: 'user_1', token: 'expired'),
      ).thenAnswer((_) async => const FailureResult(UnauthorizedFailure()));
      await repository.restore();
      expect(repository.currentStatus, const AuthUnauthenticated());
      expect(storedToken, isNull);
      expect(sequence.lastLogId, isNull);
    });
    test('stores token and login ID before publishing login success', () async {
      await sequence.save('previous-account');
      final observer = repository.status.listen((status) {
        if (status is AuthAuthenticated) {
          expect(storedToken, 'access-token');
          expect(prefs.readString(PrefsKeys.loginUserId), 'user_1');
          expect(sequence.lastLogId, isNull);
        }
      });
      await repository.login(userId: 'user_1', password: 'password');
      await observer.cancel();
      expect(repository.currentStatus, const AuthAuthenticated(_profile));
    });
    test('fails closed when token persistence fails during login', () async {
      await repository.login(userId: 'user_1', password: 'password');
      when(() => tokens.write(any())).thenThrow(const StorageFailure());
      final result = await repository.login(
        userId: 'user_1',
        password: 'password',
      );
      expect(result, isA<FailureResult<void>>());
      expect(repository.currentStatus, const AuthUnauthenticated());
      expect(storedToken, isNull);
    });
    test('signs up through the same session publication path', () async {
      await repository.signup(
        userId: 'user_1',
        password: 'password',
        passwordConfirm: 'password',
        nickname: '환자',
      );
      expect(repository.currentStatus, const AuthAuthenticated(_profile));
      expect(storedToken, 'access-token');
    });
    test(
      'failed login does not publish a session or clear local state',
      () async {
        when(
          () => source.login(userId: 'user_1', password: 'password'),
        ).thenAnswer((_) async => const FailureResult(UnauthorizedFailure()));
        await repository.login(userId: 'user_1', password: 'password');
        expect(repository.currentStatus, const AuthUnknown());
        verifyNever(() => tokens.write(any()));
      },
    );
    for (final throws in [false, true]) {
      test(
        'cleans local state when logout server fails (throws=$throws)',
        () async {
          await repository.login(userId: 'user_1', password: 'password');
          await sequence.save('latest');
          await prefs.writeString(PrefsKeys.ttsRate, 'slow');
          await prefs.writeString(PrefsKeys.speakMode, 'live');
          if (throws) {
            when(source.logout).thenThrow(Exception('offline'));
          } else {
            when(
              source.logout,
            ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
          }
          expect(await repository.logout(), isA<Success<void>>());
          expect(storedToken, isNull);
          expect(sequence.lastLogId, isNull);
          expect(repository.currentStatus, const AuthUnauthenticated());
          expect(prefs.readString(PrefsKeys.ttsRate), 'slow');
          expect(prefs.readString(PrefsKeys.speakMode), 'live');
        },
      );
    }
    test(
      'handles session expiration without a logout network request',
      () async {
        await repository.login(userId: 'user_1', password: 'password');
        await sequence.save('latest');
        expiry.emit();
        await Future<void>.delayed(Duration.zero);
        expect(repository.currentStatus, const AuthUnauthenticated());
        expect(storedToken, isNull);
        expect(sequence.lastLogId, isNull);
        verifyNever(source.logout);
      },
    );
    test('publishes onboarded profile only after successful PATCH', () async {
      await repository.login(userId: 'user_1', password: 'password');
      when(
        () => source.markOnboarded(_profile),
      ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
      await repository.markOnboarded();
      expect(repository.currentStatus, const AuthAuthenticated(_profile));
      when(
        () => source.markOnboarded(_profile),
      ).thenAnswer((_) async => const Success(null));
      await repository.markOnboarded();
      expect(repository.currentStatus, AuthAuthenticated(_profile.onboarded()));
      await repository.markOnboarded();
      verify(() => source.markOnboarded(_profile)).called(2);
    });
    test('prevents a late restore from undoing a queued logout', () async {
      storedToken = 'existing';
      final pending = Completer<Result<PatientProfile>>();
      when(
        () => source.profile(userId: 'user_1', token: 'existing'),
      ).thenAnswer((_) => pending.future);
      final restore = repository.restore();
      final logout = repository.logout();
      pending.complete(const Success(_profile));
      await Future.wait([restore, logout]);
      expect(repository.currentStatus, const AuthUnauthenticated());
      expect(storedToken, isNull);
    });
    test('attempts sequence cleanup even if keychain deletion fails', () async {
      await sequence.save('latest');
      when(tokens.clear).thenThrow(const StorageFailure());
      final result = await repository.expireSession();
      expect(result, isA<FailureResult<void>>());
      expect(sequence.lastLogId, isNull);
      expect(repository.currentStatus, const AuthUnauthenticated());
    });
  });
}
