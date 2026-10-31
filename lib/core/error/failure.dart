sealed class Failure implements Exception {
  const Failure(this.message, {this.errorCode, this.traceId});
  final String message;
  final String? errorCode;
  final String? traceId;
}

final class PermissionFailure extends Failure {
  const PermissionFailure({required this.permanent})
    : super('마이크 사용 권한이 필요합니다.');
  final bool permanent;
}

final class TtsUnavailableFailure extends Failure {
  const TtsUnavailableFailure() : super('한국어 음성을 사용할 수 없습니다.');
}

final class RecordingFailure extends Failure {
  const RecordingFailure(super.message);
}

final class TtsFailure extends Failure {
  const TtsFailure(super.message);
}

final class NetworkFailure extends Failure {
  const NetworkFailure({
    String message = '서버에 연결할 수 없습니다.',
    super.errorCode,
    super.traceId,
  }) : super(message);
}

final class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure({
    String message = '다시 로그인해 주세요.',
    super.errorCode,
    super.traceId,
  }) : super(message);
}

final class ForbiddenFailure extends Failure {
  const ForbiddenFailure({
    String message = '접근 권한이 없습니다.',
    super.errorCode,
    super.traceId,
  }) : super(message);
}

final class ConflictFailure extends Failure {
  const ConflictFailure({
    String message = '이미 사용 중인 값입니다.',
    super.errorCode,
    super.traceId,
  }) : super(message);
}

final class ValidationFailure extends Failure {
  const ValidationFailure({
    required this.fieldErrors,
    String message = '입력 내용을 확인해 주세요.',
    super.errorCode,
    super.traceId,
  }) : super(message);
  final Map<String, List<String>> fieldErrors;
}

final class PayloadTooLargeFailure extends Failure {
  const PayloadTooLargeFailure({
    String message = '음성 파일이 너무 큽니다.',
    super.errorCode,
    super.traceId,
  }) : super(message);
}

final class UnsupportedMediaFailure extends Failure {
  const UnsupportedMediaFailure({
    String message = '지원하지 않는 음성 형식입니다.',
    super.errorCode,
    super.traceId,
  }) : super(message);
}

final class TimeoutFailure extends Failure {
  const TimeoutFailure({
    String message = '요청 시간이 초과되었습니다.',
    super.errorCode,
    super.traceId,
  }) : super(message);
}

final class ServerFailure extends Failure {
  const ServerFailure({
    required this.statusCode,
    String message = '요청을 처리하지 못했습니다.',
    super.errorCode,
    super.traceId,
  }) : super(message);
  final int? statusCode;
}

final class ProtocolFailure extends Failure {
  const ProtocolFailure({
    String message = '서버 응답을 해석하지 못했습니다.',
    super.errorCode,
    super.traceId,
  }) : super(message);
}

final class StorageFailure extends Failure {
  const StorageFailure({this.cause}) : super('기기 저장소를 사용할 수 없습니다.');
  final Object? cause;
}

final class CancelledFailure extends Failure {
  const CancelledFailure() : super('요청이 취소되었습니다.');
}
