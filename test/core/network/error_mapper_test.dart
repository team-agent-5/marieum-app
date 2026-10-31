import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/network/error_mapper.dart';

DioException _http(int status, Object? body) {
  final request = RequestOptions(path: '/example');
  return DioException(
    requestOptions: request,
    type: DioExceptionType.badResponse,
    response: Response<Object?>(
      requestOptions: request,
      statusCode: status,
      data: body,
    ),
  );
}

void main() {
  group(ErrorMapper, () {
    test(
      'maps server validation fields and preserves error code and trace',
      () {
        final failure =
            ErrorMapper.map(
                  _http(400, {
                    'error_code': 'VALIDATION_ERROR',
                    'message': 'invalid',
                    'trace_id': 'trace-a',
                    'details': [
                      {'field': 'password', 'issue': 'too_short'},
                      {'field': 'password', 'issue': 'required'},
                    ],
                  }),
                )
                as ValidationFailure;
        expect(failure.fieldErrors, {
          'password': ['too_short', 'required'],
        });
        expect(failure.errorCode, 'VALIDATION_ERROR');
        expect(failure.traceId, 'trace-a');
        expect(failure.message, 'invalid');
      },
    );
    test('maps FastAPI 422 loc last elements including list indexes', () {
      final failure =
          ErrorMapper.map(
                _http(422, {
                  'detail': [
                    {
                      'loc': ['body', 'password'],
                      'msg': 'too short',
                      'type': 'value_error',
                    },
                    {
                      'loc': ['body', 'items', 0],
                      'msg': 'invalid item',
                      'type': 'type_error',
                    },
                  ],
                }),
              )
              as ValidationFailure;
      expect(failure.fieldErrors, {
        'password': ['too short'],
        '0': ['invalid item'],
      });
    });
    final statuses = <int, Type>{
      400: ValidationFailure,
      422: ValidationFailure,
      401: UnauthorizedFailure,
      403: ForbiddenFailure,
      409: ConflictFailure,
      413: PayloadTooLargeFailure,
      415: UnsupportedMediaFailure,
      503: ServerFailure,
    };
    for (final entry in statuses.entries) {
      test('maps HTTP ${entry.key} to ${entry.value}', () {
        expect(
          ErrorMapper.map(
            _http(entry.key, {
              'error_code': 'SERVER_CODE',
              'message': 'message',
              'trace_id': 'trace',
            }),
          ).runtimeType,
          entry.value,
        );
      });
    }
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.transformTimeout,
    ]) {
      test('maps $type to $TimeoutFailure', () {
        expect(
          ErrorMapper.map(
            DioException(
              requestOptions: RequestOptions(path: '/'),
              type: type,
            ),
          ),
          isA<TimeoutFailure>(),
        );
      });
    }
    for (final entry in statuses.entries) {
      test('uses string detail as HTTP ${entry.key} message', () {
        final failure = ErrorMapper.map(_http(entry.key, {'detail': 'reason'}));
        expect(failure.runtimeType, entry.value);
        expect(failure.message, 'reason');
        if (failure is ValidationFailure) {
          expect(failure.fieldErrors, isEmpty);
        }
      });
      for (final body in <Object?>[
        null,
        '<html>error</html>',
        <Object?>[],
        {'error_code': 'CODE'},
        {'error_code': 42, 'message': 'usable', 'trace_id': 42},
      ]) {
        test('retains HTTP ${entry.key} failure for partial body $body', () {
          final failure = ErrorMapper.map(_http(entry.key, body));
          expect(failure.runtimeType, entry.value);
          if (body is Map && body['message'] == 'usable') {
            expect(failure.message, 'usable');
          }
          if (body is Map && body['error_code'] == 'CODE') {
            expect(failure.errorCode, 'CODE');
          }
        });
      }
    }
    test('skips malformed server details and keeps usable fields', () {
      final failure =
          ErrorMapper.map(
                _http(400, {
                  'error_code': 'VALIDATION_ERROR',
                  'trace_id': 42,
                  'details': [
                    null,
                    {'field': 'bad'},
                    {'field': 'password', 'issue': 'mismatch'},
                    42,
                  ],
                }),
              )
              as ValidationFailure;
      expect(failure.errorCode, 'VALIDATION_ERROR');
      expect(failure.traceId, isNull);
      expect(failure.fieldErrors, {
        'password': ['mismatch'],
      });
    });
    test('skips malformed FastAPI details and keeps valid loc messages', () {
      final failure =
          ErrorMapper.map(
                _http(422, {
                  'detail': [
                    null,
                    {'loc': <Object?>[], 'msg': 'bad'},
                    {
                      'loc': ['body', 'password'],
                      'msg': 'mismatch',
                    },
                    {
                      'loc': ['body', null],
                      'msg': 'bad',
                    },
                    {
                      'loc': ['body', 'other'],
                      'msg': 42,
                    },
                  ],
                }),
              )
              as ValidationFailure;
      expect(failure.fieldErrors, {
        'password': ['mismatch'],
      });
    });
    test('keeps HTTP status over a conflicting server error code', () {
      final failure = ErrorMapper.map(
        _http(500, {
          'error_code': 'VALIDATION_ERROR',
          'message': 'server failed',
        }),
      );
      expect(failure, isA<ServerFailure>());
      expect(failure.message, 'server failed');
    });
    test('keeps response trace fallback when body trace is invalid', () {
      final error = _http(500, {'trace_id': 42, 'message': 'failed'});
      error.response!.headers.set('X-Trace-Id', 'header-trace');
      final failure = ErrorMapper.map(error);
      expect(failure.traceId, 'header-trace');
      expect(failure.message, 'failed');
    });
    test('maps connection errors to network failure', () {
      expect(
        ErrorMapper.map(
          DioException(
            requestOptions: RequestOptions(path: '/'),
            type: DioExceptionType.connectionError,
          ),
        ),
        isA<NetworkFailure>(),
      );
    });
  });
}
