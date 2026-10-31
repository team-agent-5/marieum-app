import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/network/log_interceptor.dart';

class _Handler extends RequestInterceptorHandler {}

void main() {
  group(NetworkLogInterceptor, () {
    late List<String> lines;
    late DebugPrintCallback original;

    setUp(() {
      lines = [];
      original = debugPrint;
      debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
      addTearDown(() => debugPrint = original);
    });

    test('masks credentials in logged bodies', () {
      NetworkLogInterceptor().onRequest(
        RequestOptions(
          path: '/auth/login',
          method: 'POST',
          data: {'user_id': 'demo_a', 'password': 'secret1'},
        ),
        _Handler(),
      );
      expect(lines.single, contains('/auth/login'));
      expect(lines.single, contains('demo_a'));
      expect(lines.single, isNot(contains('secret1')));
      expect(lines.single, contains('***'));
    });
  });
}
