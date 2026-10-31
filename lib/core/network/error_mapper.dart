import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:marieum_app/core/error/failure.dart';

abstract final class ErrorMapper {
  static Failure map(Object error) {
    if (error is Failure) return error;
    if (error is! DioException) return const NetworkFailure();
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
      DioExceptionType.unknown => NetworkFailure(traceId: trace),
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
    if (bodyPayload is String) {
      try {
        bodyPayload = jsonDecode(bodyPayload);
      } on FormatException {
        bodyPayload = null;
      }
    }
    if (bodyPayload is Map) {
      if (bodyPayload['error_code'] case final String value) code = value;
      if (bodyPayload['message'] case final String value) message = value;
      if (bodyPayload['trace_id'] case final String value) trace = value;
      if (message == null) {
        if (bodyPayload['detail'] case final String value) message = value;
      }
      if (bodyPayload['details'] case final List<Object?> details) {
        for (final detail in details) {
          if (detail case {
            'field': final String field,
            'issue': final String issue,
          }) {
            fields.putIfAbsent(field, () => []).add(issue);
          }
        }
      }
      if (bodyPayload['detail'] case final List<Object?> details) {
        for (final detail in details) {
          if (detail case {
            'loc': final List<Object?> location,
            'msg': final String issue,
          }) {
            if (location.isNotEmpty &&
                (location.last is String || location.last is int)) {
              fields.putIfAbsent(location.last.toString(), () => []).add(issue);
            }
          }
        }
      }
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
    if (status == 400 || status == 422) {
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
