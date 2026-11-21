import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/network/api_client.dart';
import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';
import 'package:marieum_app/features/listen/domain/repositories/listen_repository.dart';

class RemoteListenHostRepository implements ListenHostRepository {
  RemoteListenHostRepository(this._client);
  final ApiClient _client;

  @override
  Future<Result<ListenSession>> create() => _client.request(
    '/listen/sessions',
    method: 'POST',
    decode: (json) {
      final map = json! as Map<String, Object?>;
      return ListenSession(
        id: map['listen_session_id']! as String,
        joinCode: map['join_code']! as String,
        joinExpiresAt: DateTime.parse(map['join_expires_at']! as String),
        expiresAt: DateTime.parse(map['expires_at']! as String),
      );
    },
  );

  @override
  Future<Result<ListenStatus>> current() async {
    final result = await _client.request(
      '/listen/sessions/current',
      decode: (json) {
        final map = json! as Map<String, Object?>;
        return switch (map['status'] ?? map['state']) {
          'waiting' => ListenStatus.waiting,
          'connected' => ListenStatus.connected,
          'ended' => ListenStatus.ended,
          _ => throw const FormatException('status'),
        };
      },
    );
    // No session at all reads as an ended one.
    if (result case FailureResult(
      failure: ServerFailure(statusCode: 404),
    )) {
      return const Success(ListenStatus.ended);
    }
    return result;
  }

  @override
  Future<Result<void>> end() async {
    final result = await _client.request<void>(
      '/listen/sessions/current',
      method: 'DELETE',
      decode: (_) {},
    );
    // Already gone is what was wanted.
    if (result case FailureResult(
      failure: ServerFailure(statusCode: 404),
    )) {
      return const Success(null);
    }
    return result;
  }
}

class RemoteListenJoinRepository implements ListenJoinRepository {
  RemoteListenJoinRepository(this._client);
  final ApiClient _client;

  @override
  Future<Result<ListenerPass>> join(String code) => _client.request(
    '/listen/join',
    method: 'POST',
    data: {'join_code': code},
    authenticated: false,
    decode: (json) {
      final map = json! as Map<String, Object?>;
      return ListenerPass(
        token: map['listener_token']! as String,
        expiresAt: DateTime.parse(map['expires_at']! as String),
      );
    },
  );
}
