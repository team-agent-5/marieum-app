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
import 'package:marieum_app/features/listen/data/listen_remote_repository.dart';
import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';
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

void main() {
  late Dio dio;
  late SessionExpirySignal expiry;
  late _Adapter adapter;
  late ApiClient client;

  setUp(() {
    final tokens = _MockTokens();
    when(tokens.read).thenAnswer((_) async => 'patient-jwt');
    expiry = SessionExpirySignal();
    dio = createApiDio(
      config: const AppConfig(baseUrl: 'https://api.test', wsUrl: ''),
      tokens: tokens,
      expiry: expiry,
    );
    adapter = _Adapter();
    dio.httpClientAdapter = adapter;
    client = ApiClient(dio);
  });

  tearDown(() async {
    dio.close(force: true);
    await expiry.dispose();
  });

  group(RemoteListenHostRepository, () {
    test(
      'create posts with the patient login and decodes the session',
      () async {
        adapter.respond = (options) async {
          expect(options.method, 'POST');
          expect(options.path, '/listen/sessions');
          expect(options.headers['Authorization'], 'Bearer patient-jwt');
          return _json({
            'listen_session_id': 'ls_1',
            'join_code': 'K7Q2MX',
            'join_expires_at': '2026-11-22T10:10:00Z',
            'expires_at': '2026-11-22T12:00:00Z',
          }, 201);
        };
        final result = await RemoteListenHostRepository(client).create();
        expect(
          (result as Success<ListenSession>).value,
          ListenSession(
            id: 'ls_1',
            joinCode: 'K7Q2MX',
            joinExpiresAt: DateTime.utc(2026, 11, 22, 10, 10),
            expiresAt: DateTime.utc(2026, 11, 22, 12),
          ),
        );
      },
    );

    test('current reads the session, and no session as none', () async {
      adapter.respond = (_) async => _json({
        'listen_session_id': 'ls_1',
        'state': 'waiting',
        'join_code': 'K7Q2MX',
        'join_expires_at': '2026-11-22T10:10:00Z',
        'expires_at': '2026-11-22T12:00:00Z',
      });
      final repository = RemoteListenHostRepository(client);
      final waiting =
          (await repository.current() as Success<ListenSnapshot>).value;
      expect(waiting.status, ListenStatus.waiting);
      expect(waiting.session?.joinCode, 'K7Q2MX');

      adapter.respond = (_) async => _json({
        'listen_session_id': 'ls_1',
        'state': 'connected',
        'join_code': null,
        'join_expires_at': null,
        'expires_at': '2026-11-22T12:00:00Z',
      });
      final connected =
          (await repository.current() as Success<ListenSnapshot>).value;
      expect(connected.status, ListenStatus.connected);
      expect(connected.session, isNull);

      adapter.respond = (_) async =>
          _json({'error_code': 'LISTEN_NO_SESSION', 'message': 'x'}, 404);
      expect(
        (await repository.current() as Success<ListenSnapshot>).value,
        const ListenSnapshot.none(),
      );
    });

    test('only LISTEN_NO_SESSION reads as no session', () async {
      adapter.respond = (_) async =>
          _json({'error_code': 'ROUTE_NOT_FOUND', 'message': 'x'}, 404);
      final repository = RemoteListenHostRepository(client);
      expect(await repository.current(), isA<FailureResult<ListenSnapshot>>());
      expect(await repository.end(), isA<FailureResult<void>>());
    });

    test('end deletes the current session; already gone is fine', () async {
      adapter.respond = (options) async {
        expect(options.method, 'DELETE');
        expect(options.path, '/listen/sessions/current');
        return _json({'error_code': 'LISTEN_NO_SESSION'}, 404);
      };
      expect(
        await RemoteListenHostRepository(client).end(),
        isA<Success<void>>(),
      );
    });
  });

  group(RemoteListenJoinRepository, () {
    test('join sends the code without a login and decodes the pass', () async {
      adapter.respond = (options) async {
        expect(options.path, '/listen/join');
        expect(options.headers.containsKey('Authorization'), isFalse);
        expect(options.data, {'join_code': 'K7Q2MX'});
        return _json({
          'listener_token': 'tok',
          'expires_at': '2026-11-22T12:00:00Z',
        });
      };
      final result = await RemoteListenJoinRepository(client).join('K7Q2MX');
      expect(
        (result as Success<ListenerPass>).value,
        ListenerPass(token: 'tok', expiresAt: DateTime.utc(2026, 11, 22, 12)),
      );
    });

    test('join keeps the error code for the screen', () async {
      adapter.respond = (_) async =>
          _json({'error_code': 'LISTENER_ALREADY_JOINED'}, 409);
      final result = await RemoteListenJoinRepository(client).join('K7Q2MX');
      final failure = (result as FailureResult<ListenerPass>).failure;
      expect(failure, isA<ConflictFailure>());
      expect(failure.errorCode, 'LISTENER_ALREADY_JOINED');
    });
  });
}
