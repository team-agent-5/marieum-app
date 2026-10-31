import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:marieum_app/core/log/app_log.dart';

/// Logs method, path, status, duration and a short body. Credentials and
/// audio are never written.
class NetworkLogInterceptor extends Interceptor {
  static const _started = 'log_started';
  static const _maxBody = 300;
  static const _hidden = {'password', 'access_token', 'refresh_token'};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_started] = DateTime.now();
    AppLog.net('-> ${options.method} ${options.path} ${_body(options.data)}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final options = response.requestOptions;
    AppLog.net(
      '<- ${response.statusCode} ${options.method} ${options.path} '
      '${_elapsed(options)}ms ${_body(response.data)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    AppLog.net(
      '<- ${err.response?.statusCode ?? err.type.name} ${options.method} '
      '${options.path} ${_elapsed(options)}ms ${_body(err.response?.data)}',
    );
    handler.next(err);
  }

  static int _elapsed(RequestOptions options) {
    final started = options.extra[_started];
    return started is DateTime
        ? DateTime.now().difference(started).inMilliseconds
        : -1;
  }

  static String _body(Object? data) {
    if (data == null) return '';
    if (data is FormData) {
      final files = [
        for (final file in data.files) '${file.key}:${file.value.length}B',
      ];
      return 'form(${files.join(',')})';
    }
    if (data is String) {
      try {
        return _clip(jsonEncode(_mask(jsonDecode(data))));
      } on FormatException {
        return _clip(data);
      }
    }
    try {
      return _clip(jsonEncode(_mask(data)));
    } on Object {
      return data.runtimeType.toString();
    }
  }

  static Object? _mask(Object? value) => switch (value) {
    final Map<dynamic, dynamic> map => {
      for (final entry in map.entries)
        entry.key: _hidden.contains(entry.key) ? '***' : _mask(entry.value),
    },
    final List<dynamic> list => [for (final item in list) _mask(item)],
    _ => value,
  };

  static String _clip(String text) =>
      text.length <= _maxBody ? text : '${text.substring(0, _maxBody)}…';
}
