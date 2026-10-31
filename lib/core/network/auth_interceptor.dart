import 'dart:async';
import 'package:dio/dio.dart';
import 'package:marieum_app/core/network/session_expiry_signal.dart';
import 'package:marieum_app/core/storage/secure_token_store.dart';
import 'package:uuid/uuid.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this._tokens,
    required this._expiry,
    String Function()? newTraceId,
  }) : _newTraceId = newTraceId ?? const Uuid().v4;
  final SecureTokenStore _tokens;
  final SessionExpirySignal _expiry;
  final String Function() _newTraceId;
  static const skipAuth = 'skip_auth';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    unawaited(_prepare(options, handler));
  }

  Future<void> _prepare(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      String? traceId;
      for (final entry in options.headers.entries) {
        if (entry.key.toLowerCase() == 'x-trace-id' && entry.value is String) {
          traceId = entry.value as String;
        }
      }
      options.headers.removeWhere(
        (key, _) =>
            key.toLowerCase() == 'x-trace-id' ||
            key.toLowerCase() == 'authorization',
      );
      options.headers['X-Trace-Id'] = traceId == null || traceId.isEmpty
          ? _newTraceId()
          : traceId;
      if (options.extra[skipAuth] != true) {
        final token = await _tokens.read();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
      }
      handler.next(options);
    } on Object catch (error, stack) {
      handler.reject(
        DioException(requestOptions: options, error: error, stackTrace: stack),
      );
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) _expiry.emit();
    handler.next(err);
  }
}
