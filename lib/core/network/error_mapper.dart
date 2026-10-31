import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:marieum_app/core/error/failure.dart';

abstract final class ErrorMapper {
  static Failure map(Object error) {
    if (error is Failure) return error;
    if (error is FormatException || error is TypeError) {
      return const ProtocolFailure();
    }
    if (error is! DioException) return const ProtocolFailure();
    if (error.error case final Failure failure) return failure;
    final trace = _trace(error);
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => TimeoutFailure(traceId: trace),
      DioExceptionType.connectionError ||
      DioExceptionType.badCertificate => NetworkFailure(traceId: trace),
      DioExceptionType.cancel => const CancelledFailure(),
      DioExceptionType.badResponse => _http(
        error.response?.statusCode,
        error.response?.data,
        trace,
      ),
      DioExceptionType.unknown =>
        error.error is FormatException || error.error is TypeError
            ? ProtocolFailure(traceId: trace)
            : NetworkFailure(traceId: trace),
    };
  }

  static String? _trace(DioException error) {
    final response = error.response?.headers['x-trace-id'];
    if (response != null && response.isNotEmpty) return response.first;
    final request = error.requestOptions.headers['X-Trace-Id'];
    return request is String ? request : null;
  }

  static Failure _http(int? status, Object? payload, String? headerTrace) {
    var bodyPayload = payload;
    String? code;
    String? message;
    var trace = headerTrace;
    final fields = <String, List<String>>{};
    try {
      if (bodyPayload is String && bodyPayload.isNotEmpty) {
        bodyPayload = jsonDecode(bodyPayload);
      }
      if (bodyPayload == null) {
        throw const FormatException('Missing error body.');
      }
      if (bodyPayload is! Map) {
        throw const FormatException('Expected error object.');
      }
      final body = Map<String, Object?>.from(bodyPayload);
      if (body.containsKey('error_code')) {
        if (body['error_code'] is! String || body['message'] is! String) {
          throw const FormatException('Invalid error envelope.');
        }
        code = body['error_code']! as String;
        message = body['message']! as String;
        if (body['trace_id'] case final String id) {
          trace = id;
        } else if (body['trace_id'] != null) {
          throw const FormatException('Invalid trace.');
        }
        if (code == 'VALIDATION_ERROR' || status == 422) {
          final details = body['details'];
          if (details != null) {
            if (details is! List) {
              throw const FormatException('Invalid details.');
            }
            for (final detail in details) {
              if (detail case {
                'field': final String field,
                'issue': final String issue,
              }) {
                fields.putIfAbsent(field, () => []).add(issue);
              } else {
                throw const FormatException('Invalid validation detail.');
              }
            }
          }
        }
      } else if (status == 422 && body['detail'] is List) {
        code = 'VALIDATION_ERROR';
        for (final detail in body['detail']! as List) {
          if (detail is! Map ||
              detail['loc'] is! List ||
              detail['msg'] is! String) {
            throw const FormatException('Invalid FastAPI validation detail.');
          }
          final location = detail['loc']! as List;
          if (location.isEmpty ||
              (location.last is! String && location.last is! int)) {
            throw const FormatException('Missing validation field.');
          }
          fields
              .putIfAbsent(location.last.toString(), () => [])
              .add(detail['msg']! as String);
        }
      } else if ([401, 403, 409, 413, 415].contains(status)) {
        if (body['detail'] case final String detail) message = detail;
      } else {
        throw const FormatException('Unknown error schema.');
      }
    } on Object {
      // Authentication/access status remains actionable without a valid body.
      if (![401, 403, 409, 413, 415].contains(status)) {
        return ProtocolFailure(traceId: headerTrace);
      }
      code = null;
      message = null;
      trace = headerTrace;
    }
    final errors = Map<String, List<String>>.unmodifiable(
      fields.map(
        (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
      ),
    );
    if (status == 401) {
      return UnauthorizedFailure(
        message: message ?? '다시 로그인해 주세요.',
        errorCode: code,
        traceId: trace,
      );
    }
    if (status == 403) {
      return ForbiddenFailure(
        message: message ?? '접근 권한이 없습니다.',
        errorCode: code,
        traceId: trace,
      );
    }
    if (status == 409) {
      return ConflictFailure(
        message: message ?? '이미 사용 중인 값입니다.',
        errorCode: code,
        traceId: trace,
      );
    }
    if (status == 413) {
      return PayloadTooLargeFailure(
        message: message ?? '음성 파일이 너무 큽니다.',
        errorCode: code,
        traceId: trace,
      );
    }
    if (status == 415) {
      return UnsupportedMediaFailure(
        message: message ?? '지원하지 않는 음성 형식입니다.',
        errorCode: code,
        traceId: trace,
      );
    }
    if (status == 422 || code == 'VALIDATION_ERROR') {
      return ValidationFailure(
        fieldErrors: errors,
        message: message ?? '입력 내용을 확인해 주세요.',
        errorCode: code,
        traceId: trace,
      );
    }
    return ServerFailure(
      statusCode: status,
      message: message ?? '요청을 처리하지 못했습니다.',
      errorCode: code,
      traceId: trace,
    );
  }
}
