sealed class Failure implements Exception {
  const Failure(this.message);
  final String message;
}

final class PermissionFailure extends Failure {
  const PermissionFailure({required this.permanent})
    : super('마이크 사용 권한이 필요합니다.');
  final bool permanent;
}

final class TtsUnavailableFailure extends Failure {
  const TtsUnavailableFailure() : super('한국어 음성을 사용할 수 없습니다.');
}

final class TtsFailure extends Failure {
  const TtsFailure(super.message);
}
