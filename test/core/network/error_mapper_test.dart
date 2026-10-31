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
    test(
      'maps connection errors and malformed response payloads distinctly',
      () {
        expect(
          ErrorMapper.map(
            DioException(
              requestOptions: RequestOptions(path: '/'),
              type: DioExceptionType.connectionError,
            ),
          ),
          isA<NetworkFailure>(),
        );
        expect(
          ErrorMapper.map(_http(500, '<html>bad gateway</html>')),
          isA<ProtocolFailure>(),
        );
        expect(
          ErrorMapper.map(
            _http(422, {
              'detail': [
                {'loc': <Object?>[], 'msg': 'invalid'},
              ],
            }),
          ),
          isA<ProtocolFailure>(),
        );
        expect(
          ErrorMapper.map(const FormatException('invalid')),
          isA<ProtocolFailure>(),
        );
      },
    );
    test('maps a missing error body to protocol failure', () {
      expect(ErrorMapper.map(_http(500, null)), isA<ProtocolFailure>());
    });
    test('keeps unauthorized status actionable without a JSON error body', () {
      expect(
        ErrorMapper.map(_http(401, 'unauthorized')),
        isA<UnauthorizedFailure>(),
      );
    });
  });
}
