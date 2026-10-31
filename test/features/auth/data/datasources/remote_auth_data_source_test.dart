import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/config/app_config.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/network/api_client.dart';
import 'package:marieum_app/core/network/session_expiry_signal.dart';
import 'package:marieum_app/core/storage/secure_token_store.dart';
import 'package:marieum_app/features/auth/data/datasources/remote_auth_data_source.dart';
import 'package:marieum_app/features/auth/data/dto/auth_session_dto.dart';
import 'package:marieum_app/features/auth/domain/entities/patient_profile.dart';
import 'package:mocktail/mocktail.dart';

class _MockTokens extends Mock implements SecureTokenStore {}

class _Adapter implements HttpClientAdapter {
  late Future<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => respond(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? data, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(data),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);
const _patient = <String, Object>{
  'id': 42,
  'nickname': '환자',
  'onboarding_completed': false,
};
void main() {
  group(RemoteAuthDataSource, () {
    late Dio dio;
    late SessionExpirySignal expiry;
    late _Adapter adapter;
    late RemoteAuthDataSource source;
    setUp(() {
      final tokens = _MockTokens();
      when(tokens.read).thenAnswer((_) async => 'existing');
      expiry = SessionExpirySignal();
      dio = createApiDio(
        config: const AppConfig(baseUrl: 'https://api.test', wsUrl: ''),
        tokens: tokens,
        expiry: expiry,
      );
      adapter = _Adapter();
      dio.httpClientAdapter = adapter;
      source = RemoteAuthDataSource(ApiClient(dio));
    });
    tearDown(() async {
      dio.close(force: true);
      await expiry.dispose();
    });
    test(
      'sends signup confirmation without device ID or bearer '
      'and decodes patient ID',
      () async {
        adapter.respond = (options) async {
          expect(options.path, '/auth/signup');
          expect(options.method, 'POST');
          expect(options.headers['Authorization'], isNull);
          expect(options.data, {
            'user_id': 'user_1',
            'password': 'password',
            'password_confirm': 'password',
            'nickname': '환자',
          });
          return _json({
            'access_token': 'new-token',
            'token_type': 'bearer',
            'expires_in': 31536000,
            'patient': _patient,
          }, 201);
        };
        final result =
            await source.signup(
                  userId: 'user_1',
                  password: 'password',
                  passwordConfirm: 'password',
                  nickname: '환자',
                )
                as Success<AuthSessionDto>;
        expect(result.value.accessToken, 'new-token');
        expect(result.value.profile.id, '42');
        expect(result.value.profile.userId, 'user_1');
      },
    );
    test(
      'incorrect login returns unauthorized without a session-expired signal',
      () async {
        var expirations = 0;
        final subscription = expiry.expired.listen((_) => expirations++);
        addTearDown(subscription.cancel);
        adapter.respond = (options) async {
          expect(options.path, '/auth/login');
          expect(options.headers['Authorization'], isNull);
          expect(options.data, {
            'user_id': 'user_1',
            'password': 'wrong-password',
          });
          return _json({'detail': 'invalid credentials'}, 401);
        };
        final result =
            await source.login(userId: 'user_1', password: 'wrong-password')
                as FailureResult<AuthSessionDto>;
        expect(result.failure, isA<UnauthorizedFailure>());
        expect(expirations, 0);
      },
    );
    test(
      'restores profile using prefs user ID '
      'instead of requiring a response user ID',
      () async {
        adapter.respond = (options) async {
          expect(options.path, '/patient/me');
          expect(options.headers['Authorization'], 'Bearer existing');
          return _json(_patient);
        };
        final result =
            await source.profile(userId: 'user_1', token: 'existing')
                as Success<PatientProfile>;
        expect(result.value.userId, 'user_1');
        expect(result.value.onboardingCompleted, isFalse);
      },
    );
    test('accepts logout 204 and PATCHes onboarding completion', () async {
      adapter.respond = (options) async {
        if (options.path == '/auth/logout') {
          expect(options.method, 'POST');
          return ResponseBody.fromString('', 204);
        }
        expect(options.path, '/patient/preferences');
        expect(options.method, 'PATCH');
        expect(options.data, {'onboarding_completed': true});
        return _json({'onboarding_completed': true});
      };
      expect(await source.logout(), isA<Success<void>>());
      expect(
        await source.markOnboarded(
          const PatientProfile(
            id: '42',
            nickname: '환자',
            onboardingCompleted: false,
            userId: 'user_1',
          ),
        ),
        isA<Success<void>>(),
      );
    });
    test(
      'rejects malformed successful auth response without storing a session',
      () async {
        adapter.respond = (_) async => _json({
          'access_token': 'token',
          'patient': {'id': 42},
        });
        final result =
            await source.login(userId: 'user_1', password: 'password')
                as FailureResult<AuthSessionDto>;
        expect(result.failure, isA<ProtocolFailure>());
      },
    );
  });
}
