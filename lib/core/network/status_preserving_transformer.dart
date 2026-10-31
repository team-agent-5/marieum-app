import 'package:dio/dio.dart';
import 'package:marieum_app/core/error/failure.dart';

/// Keeps HTTP errors available even when their JSON body is malformed.
class StatusPreservingTransformer extends BackgroundTransformer {
  @override
  Future<Object?> transformResponse(
    RequestOptions options,
    ResponseBody responseBody,
  ) async {
    final status = responseBody.statusCode;
    if (status < 200 || status >= 300) {
      return super.transformResponse(
        options.copyWith(responseType: ResponseType.plain),
        responseBody,
      );
    }
    try {
      return await super.transformResponse(options, responseBody);
    } on FormatException {
      throw const ProtocolFailure();
    }
  }
}
