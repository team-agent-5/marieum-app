import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';
import 'package:marieum_app/features/listen/domain/repositories/listen_repository.dart';

enum ListenHostPhase {
  /// The session is being opened.
  creating,

  /// The code is shown and the other phone has not joined yet.
  waiting,

  /// The other phone is listening.
  connected,

  /// Nobody joined before the code ran out; [ListenHostCubit.renew] makes a
  /// new one.
  codeExpired,

  /// The other phone left and did not come back in time; the code was used
  /// up, so [ListenHostCubit.renew] makes a new one.
  left,

  /// The session is over, ended here or by the server.
  ended,

  /// The session could not be opened; [ListenHostCubit.renew] tries again.
  failed,
}

class ListenHostState extends Equatable {
  const ListenHostState({
    this.phase = ListenHostPhase.creating,
    this.session,
    this.joinRemaining = Duration.zero,
    this.failure,
  });

  final ListenHostPhase phase;
  final ListenSession? session;

  /// How long the code still joins, counted down each second while waiting.
  final Duration joinRemaining;
  final Failure? failure;

  ListenHostState copyWith({
    ListenHostPhase? phase,
    ListenSession? session,
    Duration? joinRemaining,
    Failure? Function()? failure,
  }) => ListenHostState(
    phase: phase ?? this.phase,
    session: session ?? this.session,
    joinRemaining: joinRemaining ?? this.joinRemaining,
    failure: failure == null ? this.failure : failure(),
  );

  @override
  List<Object?> get props => [phase, session, joinRemaining, failure];
}

/// The patient's listening session: opens it, shows the code until the other
/// phone joins, and follows its status.
class ListenHostCubit extends Cubit<ListenHostState> {
  ListenHostCubit({
    required this._repository,
    DateTime Function()? now,
    this.pollEvery = const Duration(seconds: 2),
  }) : _now = now ?? DateTime.now,
       super(const ListenHostState());

  final ListenHostRepository _repository;
  final DateTime Function() _now;

  /// How often the status is asked for.
  final Duration pollEvery;

  Timer? _clock;
  Timer? _poll;
  bool _polling = false;
  bool _ending = false;
  int _revision = 0;

  /// The session being opened, so [end] can wait for it.
  Future<Result<ListenSession>>? _creating;

  /// Opens the session; called once when the page opens.
  Future<void> start() => _open();

  /// A new code after the old one ran out, or another try after a failure.
  Future<void> renew() => _open();

  /// Ends the session; the page closes afterwards. A session still being
  /// opened is waited for and then ended, with a single DELETE: the page
  /// waits for this before closing, so no later screen's session is hit.
  Future<void> end() async {
    if (_ending) return;
    _ending = true;
    _stopTimers();
    _revision++;
    final endedThere = state.phase == ListenHostPhase.ended;
    if (!isClosed) emit(state.copyWith(phase: ListenHostPhase.ended));
    final creating = _creating;
    if (creating != null) {
      // Ended after asking only if the server made one.
      if (await creating is! Success) return;
    } else if (endedThere) {
      return;
    }
    await _repository.end();
  }

  Future<void> _open() async {
    // One POST at a time: a second tap while one is under way would leave a
    // session [end] never waits for.
    if (_ending || _creating != null) return;
    _stopTimers();
    final revision = ++_revision;
    emit(ListenHostState(session: state.session));
    final creating = _creating = _repository.create();
    final result = await creating;
    if (identical(_creating, creating)) _creating = null;
    if (_ending) return;
    if (isClosed || revision != _revision) return;
    switch (result) {
      case Success(value: final session):
        emit(
          ListenHostState(
            phase: ListenHostPhase.waiting,
            session: session,
            joinRemaining: _remaining(session),
          ),
        );
        _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
        _poll = Timer.periodic(pollEvery, (_) => unawaited(_check()));
      case FailureResult(:final failure):
        emit(
          state.copyWith(phase: ListenHostPhase.failed, failure: () => failure),
        );
    }
  }

  Duration _remaining(ListenSession session) {
    final left = session.joinExpiresAt.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  void _tick() {
    final session = state.session;
    if (isClosed || session == null) return;
    if (_now().isAfter(session.expiresAt)) {
      _stopTimers();
      emit(state.copyWith(phase: ListenHostPhase.ended));
      return;
    }
    if (state.phase != ListenHostPhase.waiting) return;
    final remaining = _remaining(session);
    emit(state.copyWith(joinRemaining: remaining));
    // The status is asked once more before giving up on the code, in case
    // the other phone joined in its last seconds.
    if (remaining == Duration.zero) unawaited(_check(expiring: true));
  }

  Future<void> _check({bool expiring = false}) async {
    if (_polling) return;
    _polling = true;
    final revision = _revision;
    try {
      final result = await _repository.current();
      if (isClosed || revision != _revision) return;
      if (result case Success(value: final status)) {
        switch (status) {
          case ListenStatus.connected:
            if (state.phase != ListenHostPhase.connected) {
              emit(state.copyWith(phase: ListenHostPhase.connected));
            }
          case ListenStatus.waiting:
            if (state.phase == ListenHostPhase.connected) {
              // The other phone left for good; a new code lets it back in.
              _stopTimers();
              emit(state.copyWith(phase: ListenHostPhase.left));
            } else if (expiring) {
              _stopTimers();
              emit(state.copyWith(phase: ListenHostPhase.codeExpired));
            }
          case ListenStatus.ended:
            _stopTimers();
            emit(state.copyWith(phase: ListenHostPhase.ended));
        }
      }
    } finally {
      _polling = false;
    }
  }

  void _stopTimers() {
    _clock?.cancel();
    _poll?.cancel();
    _clock = _poll = null;
  }

  @override
  Future<void> close() {
    _stopTimers();
    return super.close();
  }
}
