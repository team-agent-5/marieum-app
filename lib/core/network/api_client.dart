import 'package:dio/dio.dart';
import 'package:marieum_app/core/audio/recorded_audio.dart';
import 'package:marieum_app/core/config/app_config.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/network/auth_interceptor.dart';
import 'package:marieum_app/core/network/error_mapper.dart';
import 'package:marieum_app/core/network/session_expiry_signal.dart';
import 'package:marieum_app/core/storage/secure_token_store.dart';

Dio createApiDio({
  required AppConfig config,
  required SecureTokenStore tokens,
  required SessionExpirySignal expiry,
  String Function()? newTraceId,
}) {
  return Dio(
      BaseOptions(
        baseUrl: config.baseUrl,
        connectTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        headers: {'Accept': Headers.jsonContentType},
      ),
    )
    ..interceptors.add(
      AuthInterceptor(tokens: tokens, expiry: expiry, newTraceId: newTraceId),
    );
}

class ApiClient {
  ApiClient(this._dio);
  final Dio _dio;

  static Duration timeoutFor(String path) => switch (path) {
    '/phrase/transcribe' => const Duration(seconds: 8),
    '/phrase/suggest' => const Duration(seconds: 3),
    _ => const Duration(seconds: 5),
  };

  Future<Result<T>> request<T>(
    String path, {
    required T Function(Object?) decode,
    String method = 'GET',
    Object? data,
    Map<String, Object?>? query,
    bool authenticated = true,
    String? traceId,
    CancelToken? cancelToken,
  }) async {
    try {
      final timeout = timeoutFor(path);
      final response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: query,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          sendTimeout: timeout,
          receiveTimeout: timeout,
          headers: {'X-Trace-Id': ?traceId},
          extra: {AuthInterceptor.skipAuth: !authenticated},
        ),
      );
      return Success(decode(response.data));
    } on Object catch (error) {
      return FailureResult(ErrorMapper.map(error));
    }
  }

  Future<Result<T>> uploadAudio<T>(
    RecordedAudio audio, {
    required T Function(Object?) decode,
    String? traceId,
    CancelToken? cancelToken,
  }) {
    if (audio.bytes.length > 2 * 1024 * 1024) {
      return Future.value(const FailureResult(PayloadTooLargeFailure()));
    }
    if (audio.bytes.isEmpty ||
        audio.durationMs < 0 ||
        audio.durationMs > 15000) {
      return Future.value(
        const FailureResult(
          ValidationFailure(
            fieldErrors: {
              'audio': ['WAV bytes와 0~15000ms 길이가 필요합니다.'],
            },
          ),
        ),
      );
    }
    final form = FormData.fromMap({
      'audio': MultipartFile.fromBytes(
        audio.bytes,
        filename: 'utterance.wav',
        contentType: DioMediaType('audio', 'wav'),
      ),
      'duration_ms': audio.durationMs.toString(),
    });
    return request(
      '/phrase/transcribe',
      method: 'POST',
      data: form,
      decode: decode,
      traceId: traceId,
      cancelToken: cancelToken,
    );
  }
}
