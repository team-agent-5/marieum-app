import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/recorded_audio.dart';
import 'package:marieum_app/core/config/app_config.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/network/api_client.dart';
import 'package:marieum_app/core/network/session_expiry_signal.dart';
import 'package:marieum_app/core/storage/secure_token_store.dart';
import 'package:mocktail/mocktail.dart';

class _MockTokens extends Mock implements SecureTokenStore {}

class _Adapter implements HttpClientAdapter {
  late Future<ResponseBody> Function(RequestOptions, Stream<Uint8List>?)
  respond;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls++;
    return respond(options, requestStream);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String value, [int status = 200]) => ResponseBody.fromString(
  value,
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);
String _decode(Object? value) =>
    (value! as Map<String, Object?>)['trace_id']! as String;

void main() {
  group(ApiClient, () {
    late _MockTokens tokens;
    late SessionExpirySignal expiry;
    late Dio dio;
    late ApiClient client;
    late _Adapter adapter;
    setUp(() {
      tokens = _MockTokens();
      when(tokens.read).thenAnswer((_) async => 'test-token');
      expiry = SessionExpirySignal();
      dio = createApiDio(
        config: const AppConfig(baseUrl: 'https://api.example.test', wsUrl: ''),
        tokens: tokens,
        expiry: expiry,
        newTraceId: () => 'generated-trace',
      );
      adapter = _Adapter()
        ..respond = (_, _) async => _json('{"trace_id":"ok"}');
      dio.httpClientAdapter = adapter;
      client = ApiClient(dio);
    });
    tearDown(() async {
      dio.close(force: true);
      await expiry.dispose();
    });

    test(
      'uses configured base URL and injects token plus a fresh request trace',
      () async {
        adapter.respond = (options, _) async {
          expect(options.uri.toString(), 'https://api.example.test/patient/me');
          expect(options.headers['Authorization'], 'Bearer test-token');
          expect(options.headers['X-Trace-Id'], 'generated-trace');
          expect(options.connectTimeout, const Duration(seconds: 5));
          return _json('{"trace_id":"ok"}');
        };
        expect(
          await client.request('/patient/me', decode: _decode),
          isA<Success<String>>(),
        );
      },
    );
    test('preserves a caller trace for related utterance requests', () async {
      adapter.respond = (options, _) async {
        expect(options.headers['X-Trace-Id'], 'utterance-trace');
        return _json('{"trace_id":"ok"}');
      };
      await client.request(
        '/phrase/selection',
        method: 'POST',
        traceId: 'utterance-trace',
        decode: _decode,
      );
    });
    test(
      'allows login without a stored token or a stale Authorization header',
      () async {
        dio.options.headers['authorization'] = 'Bearer stale';
        adapter.respond = (options, _) async {
          expect(
            options.headers.keys.any(
              (key) => key.toLowerCase() == 'authorization',
            ),
            isFalse,
          );
          return _json('{"trace_id":"ok"}');
        };
        await client.request(
          '/auth/login',
          method: 'POST',
          authenticated: false,
          decode: _decode,
        );
        verifyNever(tokens.read);
      },
    );
    test(
      'reads the current token for each request '
      'instead of retaining a stale bearer',
      () async {
        var token = 'first';
        when(tokens.read).thenAnswer((_) async => token);
        adapter.respond = (options, _) async {
          expect(options.headers['Authorization'], 'Bearer $token');
          return _json('{"trace_id":"ok"}');
        };
        await client.request('/patient/me', decode: _decode);
        token = 'second';
        await client.request('/patient/me', decode: _decode);
        verify(tokens.read).called(2);
      },
    );
    for (final status in [401, 403]) {
      test('maps $status and emits expiration only for 401', () async {
        var events = 0;
        final subscription = expiry.expired.listen((_) {
          events++;
        });
        addTearDown(subscription.cancel);
        adapter.respond = (_, _) async => _json(
          '{"error_code":"ACCESS","message":"denied",'
          '"trace_id":"server-trace"}',
          status,
        );
        final result =
            await client.request('/patient/me', decode: _decode)
                as FailureResult<String>;
        expect(
          result.failure,
          status == 401 ? isA<UnauthorizedFailure>() : isA<ForbiddenFailure>(),
        );
        expect(result.failure.traceId, 'server-trace');
        expect(events, status == 401 ? 1 : 0);
      });
    }
    for (final token in <String?>[null, '', 'existing-token']) {
      for (final authenticated in [false, true]) {
        test(
          '401 with token=$token and authenticated=$authenticated '
          'expires only a request sent with a bearer',
          () async {
            when(tokens.read).thenAnswer((_) async => token);
            dio.options.headers['authorization'] = 'Bearer stale';
            var events = 0;
            final subscription = expiry.expired.listen((_) => events++);
            addTearDown(subscription.cancel);
            adapter.respond = (options, _) async {
              expect(
                options.headers['Authorization'],
                authenticated && token != null && token.isNotEmpty
                    ? 'Bearer $token'
                    : isNull,
              );
              return _json('{"detail":"invalid credentials"}', 401);
            };
            final result =
                await client.request(
                      authenticated ? '/patient/me' : '/auth/login',
                      authenticated: authenticated,
                      decode: _decode,
                    )
                    as FailureResult<String>;
            expect(result.failure, isA<UnauthorizedFailure>());
            expect(
              events,
              authenticated && token != null && token.isNotEmpty ? 1 : 0,
            );
          },
        );
      }
    }
    test('retains HTTP status when a JSON error body is malformed', () async {
      adapter.respond = (_, _) async => _json('{broken json', 400);
      final result =
          await client.request('/auth/signup', decode: _decode)
              as FailureResult<String>;
      expect(result.failure, isA<ValidationFailure>());
    });
    test('maps malformed successful JSON to protocol failure', () async {
      adapter.respond = (_, _) async => _json('{broken json');
      final result =
          await client.request('/patient/me', decode: _decode)
              as FailureResult<String>;
      expect(result.failure, isA<ProtocolFailure>());
    });
    test('does not send a request when token storage fails', () async {
      when(tokens.read).thenThrow(const StorageFailure());
      final result =
          await client.request('/patient/me', decode: _decode)
              as FailureResult<String>;
      expect(result.failure, isA<StorageFailure>());
      expect(adapter.calls, 0);
    });
    test(
      'maps invalid successful-response parsing to protocol failure',
      () async {
        final result =
            await client.request<int>(
                  '/patient/me',
                  decode: (value) => value! as int,
                )
                as FailureResult<int>;
        expect(result.failure, isA<ProtocolFailure>());
      },
    );
    test(
      'uploads a memory WAV as one audio file '
      'with duration and an eight-second timeout',
      () async {
        final audio = encodePcmWav(Uint8List(320));
        adapter.respond = (options, stream) async {
          expect(options.path, '/phrase/transcribe');
          expect(options.method, 'POST');
          expect(options.receiveTimeout, const Duration(seconds: 8));
          final form = options.data! as FormData;
          expect(form.fields.single.key, 'duration_ms');
          expect(form.fields.single.value, '10');
          expect(form.files.single.key, 'audio');
          expect(form.files.single.value.contentType.toString(), 'audio/wav');
          expect(form.files.single.value.filename, 'utterance.wav');
          final body = BytesBuilder();
          await stream!.forEach(body.add);
          expect(
            latin1.decode(body.takeBytes()),
            contains(latin1.decode(audio.bytes)),
          );
          expect(
            options.contentType,
            startsWith(Headers.multipartFormDataContentType),
          );
          return _json('{"trace_id":"ok"}');
        };
        expect(
          await client.uploadAudio(audio, decode: _decode),
          isA<Success<String>>(),
        );
      },
    );
    test(
      'rejects files beyond two MiB and invalid duration without network calls',
      () async {
        final large = RecordedAudio(
          bytes: Uint8List(2 * 1024 * 1024 + 1),
          durationMs: 10000,
        );
        final oversized =
            await client.uploadAudio(large, decode: _decode)
                as FailureResult<String>;
        expect(oversized.failure, isA<PayloadTooLargeFailure>());
        for (final duration in [-1, 15001]) {
          final result = await client.uploadAudio(
            RecordedAudio(bytes: Uint8List(44), durationMs: duration),
            decode: _decode,
          );
          expect(
            result,
            isA<FailureResult<String>>().having(
              (value) => value.failure,
              'failure',
              isA<ValidationFailure>(),
            ),
          );
        }
        expect(adapter.calls, 0);
      },
    );
    for (final entry in {
      '/phrase/suggest': 3,
      '/phrase/selection': 5,
      '/phrase/bypass': 5,
    }.entries) {
      test('applies the ${entry.value}s deadline for ${entry.key}', () async {
        adapter.respond = (options, _) async {
          expect(options.receiveTimeout, Duration(seconds: entry.value));
          return _json('{"trace_id":"ok"}');
        };
        await client.request(entry.key, decode: _decode);
      });
    }
  });
}
