import 'dart:async';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/network/session_expiry_signal.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/core/storage/secure_token_store.dart';
import 'package:marieum_app/core/storage/sequence_store.dart';
import 'package:marieum_app/features/auth/data/datasources/auth_data_source.dart';
import 'package:marieum_app/features/auth/data/dto/auth_session_dto.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required this._source,
    required this._tokens,
    required this._prefs,
    required this._sequence,
    required SessionExpirySignal expiry,
  }) {
    _expiry = expiry.expired.listen((_) {
      unawaited(expireSession());
    });
  }
  final AuthDataSource _source;
  final SecureTokenStore _tokens;
  final PrefsStore _prefs;
  final SequenceStore _sequence;
  final _changes = StreamController<AuthStatus>.broadcast(sync: true);
  late final StreamSubscription<void> _expiry;
  AuthStatus _current = const AuthUnknown();
  Future<void> _tail = Future.value();
  @override
  AuthStatus get currentStatus => _current;
  @override
  Stream<AuthStatus> get status => Stream.multi((controller) {
    final subscription = _changes.stream.listen(
      controller.addSync,
      onDone: controller.closeSync,
    );
    controller
      ..addSync(_current)
      ..onCancel = subscription.cancel;
  }, isBroadcast: true);
  void _publish(AuthStatus value) {
    _current = value;
    _changes.add(value);
  }

  // Serialize session mutations so late restoration cannot overwrite logout.
  Future<Result<void>> _run(
    Future<Result<void>> Function() operation, {
    bool restoring = false,
  }) {
    final result = _tail.then((_) async {
      try {
        return await operation();
      } on Object catch (error) {
        final failure = error is Failure ? error : StorageFailure(cause: error);
        if (restoring) _publish(AuthUnknown(failure: failure));
        return FailureResult<void>(failure);
      }
    });
    _tail = result.then((_) {});
    return result;
  }

  @override
  Future<Result<void>> restore() => _run(() async {
    _publish(const AuthUnknown());
    final token = await _tokens.read();
    if (token == null || token.isEmpty) return _clearLocal();
    final result = await _source.profile(
      userId: _prefs.readString(PrefsKeys.loginUserId) ?? '',
      token: token,
    );
    switch (result) {
      case Success(:final value):
        _publish(AuthAuthenticated(value));
        return const Success(null);
      case FailureResult(:final failure):
        if (failure is UnauthorizedFailure) return _clearLocal();
        _publish(AuthUnknown(failure: failure));
        return FailureResult(failure);
    }
  }, restoring: true);
  Future<Result<void>> _accept(Result<AuthSessionDto> result) async {
    switch (result) {
      case FailureResult(:final failure):
        return FailureResult(failure);
      case Success(:final value):
        try {
          await _tokens.write(value.accessToken);
          await _prefs.writeString(PrefsKeys.loginUserId, value.profile.userId);
          await _sequence.clear();
        } on Object {
          await _clearLocal();
          rethrow;
        }
        _publish(AuthAuthenticated(value.profile));
        return const Success(null);
    }
  }

  @override
  Future<Result<void>> login({
    required String userId,
    required String password,
  }) => _run(
    () async =>
        _accept(await _source.login(userId: userId, password: password)),
  );
  @override
  Future<Result<void>> signup({
    required String userId,
    required String password,
    required String passwordConfirm,
    required String nickname,
  }) => _run(
    () async => _accept(
      await _source.signup(
        userId: userId,
        password: password,
        passwordConfirm: passwordConfirm,
        nickname: nickname,
      ),
    ),
  );
  Future<Result<void>> _clearLocal() async {
    Failure? failure;
    try {
      await _tokens.clear();
    } on Object catch (error) {
      failure = error is Failure ? error : StorageFailure(cause: error);
    }
    try {
      await _sequence.clear();
    } on Object catch (error) {
      failure ??= error is Failure ? error : StorageFailure(cause: error);
    }
    _publish(const AuthUnauthenticated());
    return failure == null ? const Success(null) : FailureResult(failure);
  }

  @override
  Future<Result<void>> logout() => _run(() async {
    try {
      await _source.logout();
    } on Object {
      /* Local cleanup is authoritative. */
    }
    return _clearLocal();
  });
  @override
  Future<Result<void>> expireSession() => _run(_clearLocal);
  @override
  Future<Result<void>> markOnboarded() => _run(() async {
    final current = _current;
    if (current is! AuthAuthenticated) {
      return const FailureResult(UnauthorizedFailure());
    }
    if (current.profile.onboardingCompleted) return const Success(null);
    final result = await _source.markOnboarded(current.profile);
    if (result case FailureResult(:final failure)) {
      return FailureResult(failure);
    }
    _publish(AuthAuthenticated(current.profile.onboarded()));
    return const Success(null);
  });
  @override
  Future<void> dispose() async {
    await _expiry.cancel();
    await _tail;
    await _changes.close();
  }
}
