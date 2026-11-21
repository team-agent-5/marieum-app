import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/log/app_log.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';
import 'package:marieum_app/features/listen/domain/repositories/listen_repository.dart';
import 'package:marieum_app/features/listen/domain/repositories/listener_channel.dart';

enum ListenerPhase {
  /// The code is typed or scanned.
  entering,

  /// The code is being checked.
  joining,

  /// Joined; the first connection is being opened.
  connecting,

  /// Sentences from the patient are said aloud as they come.
  listening,

  /// The connection dropped and is being opened again.
  reconnecting,

  /// The session is over; [ListenerState.endReason] says why.
  ended,
}

/// A sentence the patient sent, newest last.
class HeardLine extends Equatable {
  const HeardLine({
    required this.utteranceId,
    required this.text,
    required this.heardAt,
  });

  final String utteranceId;
  final String text;
  final DateTime heardAt;

  @override
  List<Object?> get props => [utteranceId, text, heardAt];
}

class ListenerState extends Equatable {
  const ListenerState({
    this.phase = ListenerPhase.entering,
    this.lines = const [],
    this.speakingId,
    this.error,
    this.endReason,
  });

  final ListenerPhase phase;
  final List<HeardLine> lines;

  /// The line being said aloud now.
  final String? speakingId;

  /// What to tell the user about the last code or connection, in Korean.
  final String? error;
  final ListenEndReason? endReason;

  ListenerState copyWith({
    ListenerPhase? phase,
    List<HeardLine>? lines,
    String? Function()? speakingId,
    String? Function()? error,
    ListenEndReason? endReason,
  }) => ListenerState(
    phase: phase ?? this.phase,
    lines: lines ?? this.lines,
    speakingId: speakingId == null ? this.speakingId : speakingId(),
    error: error == null ? this.error : error(),
    endReason: endReason ?? this.endReason,
  );

  @override
  List<Object?> get props => [phase, lines, speakingId, error, endReason];
}

/// The other phone: joins the patient's session with a code and says each
/// sentence the patient sends aloud, in order.
class ListenerCubit extends Cubit<ListenerState> {
  ListenerCubit({
    required this._repository,
    required this._channel,
    required this._tts,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       super(const ListenerState());

  /// Lines kept on screen.
  static const maxLines = 50;

  final ListenJoinRepository _repository;
  final ListenerChannel _channel;
  final PlaybackTtsPort _tts;
  final DateTime Function() _now;

  ListenerConnection? _connection;

  // Cancelled in _drop.
  // ignore: cancel_subscriptions
  StreamSubscription<ListenerEvent>? _events;
  final _queue = <HeardLine>[];
  Future<void>? _speaking;

  /// Counts joins and leaves, so a join answered after leaving is dropped.
  int _attempt = 0;

  /// A typed code; one that is not six valid characters is refused here.
  Future<void> join(String raw) async {
    final code = JoinCode.normalize(raw);
    if (code == null) {
      emit(state.copyWith(error: () => '6자리 코드를 확인해 주세요.'));
      return;
    }
    await _join(code);
  }

  /// A scanned QR payload; one that is not a Marieum code is refused here.
  Future<void> joinScanned(String payload) async {
    final code = JoinCode.fromScan(payload);
    if (code == null) {
      emit(state.copyWith(error: () => '마리음 연결 QR이 아니에요.'));
      return;
    }
    await _join(code);
  }

  Future<void> _join(String code) async {
    if (state.phase != ListenerPhase.entering &&
        state.phase != ListenerPhase.ended) {
      return;
    }
    final attempt = ++_attempt;
    emit(const ListenerState(phase: ListenerPhase.joining));
    final result = await _repository.join(code);
    // Left, or closed, while the code was being checked.
    if (isClosed || attempt != _attempt) return;
    switch (result) {
      case Success(value: final pass):
        emit(state.copyWith(phase: ListenerPhase.connecting));
        final connection = _connection = _channel.connect(pass);
        _events = connection.events.listen(_onEvent);
      case FailureResult(:final failure):
        emit(
          ListenerState(
            error: switch (failure.errorCode) {
              'LISTEN_CODE_INVALID' => '코드가 맞지 않거나 시간이 지났어요.',
              'LISTENER_ALREADY_JOINED' => '이미 다른 폰이 연결되어 있어요.',
              'RATE_LIMITED' => '잠시 뒤에 다시 시도해 주세요.',
              _ => failure.message,
            },
          ),
        );
    }
  }

  void _onEvent(ListenerEvent event) {
    if (isClosed) return;
    switch (event) {
      case ListenerConnected():
        emit(state.copyWith(phase: ListenerPhase.listening, error: () => null));
      case ListenerReconnecting():
        emit(state.copyWith(phase: ListenerPhase.reconnecting));
      case ListenerSay(:final utteranceId, :final text):
        if (state.lines.any((line) => line.utteranceId == utteranceId)) return;
        final line = HeardLine(
          utteranceId: utteranceId,
          text: text,
          heardAt: _now(),
        );
        final lines = [...state.lines, line];
        emit(
          state.copyWith(
            lines: lines.length > maxLines
                ? lines.sublist(lines.length - maxLines)
                : lines,
          ),
        );
        _queue.add(line);
        _speaking ??= _speakQueued().whenComplete(() => _speaking = null);
      case ListenerEnded(:final reason):
        unawaited(_finish(reason));
    }
  }

  Future<void> _speakQueued() async {
    while (_queue.isNotEmpty && !isClosed) {
      final line = _queue.removeAt(0);
      // Reported over the connection the line came on; once that one is
      // closed, a later session never hears about it.
      final connection = _connection;
      final result = await _tts.speakWithPlayback(
        line.text,
        onStarted: () {
          if (!isClosed) {
            emit(state.copyWith(speakingId: () => line.utteranceId));
          }
        },
        onEnded: () {},
      );
      if (isClosed) return;
      emit(state.copyWith(speakingId: () => null));
      if (result is Success) {
        if (identical(connection, _connection)) {
          connection?.played(line.utteranceId);
        }
      } else {
        AppLog.speak('listener line ${line.utteranceId} not spoken');
      }
    }
  }

  /// The sentence being said is finished, as the patient may end right after
  /// sending it; the ones waiting are dropped.
  Future<void> _finish(ListenEndReason reason) async {
    _queue.clear();
    await _drop();
    if (isClosed) return;
    emit(
      state.copyWith(
        phase: ListenerPhase.ended,
        endReason: reason,
        speakingId: () => null,
      ),
    );
  }

  /// Stops listening; the page closes afterwards.
  Future<void> leave() async {
    _attempt++;
    _queue.clear();
    // The connection goes first so no new sentence starts after the stop.
    await _drop();
    await _tts.stop();
  }

  Future<void> _drop() async {
    final events = _events;
    final connection = _connection;
    _events = null;
    _connection = null;
    await events?.cancel();
    await connection?.close();
  }

  @override
  Future<void> close() async {
    _queue.clear();
    await _drop();
    return super.close();
  }
}
