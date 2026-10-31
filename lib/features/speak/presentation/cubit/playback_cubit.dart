import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/haptics/haptics.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';

enum PlaybackStatus { initial, playing, completed, failed, closed }

class PlaybackState extends Equatable {
  const PlaybackState({
    required this.text,
    this.status = PlaybackStatus.initial,
    this.failure,
  });
  final String text;
  final PlaybackStatus status;
  final Failure? failure;
  @override
  List<Object?> get props => [text, status, failure];
}

class PlaybackCubit extends Cubit<PlaybackState> {
  PlaybackCubit({
    required PlaybackRequest request,
    required this._tts,
    required this._haptics,
  }) : super(PlaybackState(text: request.text));
  final TtsPort _tts;
  final VoiceHaptics _haptics;
  Timer? _returnTimer;
  int _revision = 0;
  bool _started = false;
  bool _closing = false;
  bool _endFeedbackSent = false;
  Future<void>? _stopOperation;
  Future<void> _feedback(VoiceHaptic event) async {
    try {
      await _haptics.trigger(event);
    } on Object {
      /* Speech must survive unavailable haptics. */
    }
  }

  void _endFeedback() {
    if (!_started || _endFeedbackSent) return;
    _endFeedbackSent = true;
    unawaited(_feedback(VoiceHaptic.playbackStopped));
  }

  Future<void> start() async {
    if (_started || _closing || isClosed) return;
    _started = true;
    final revision = ++_revision;
    emit(PlaybackState(text: state.text, status: PlaybackStatus.playing));
    unawaited(_feedback(VoiceHaptic.playbackStarted));
    Result<void> result;
    try {
      result = await _tts.speak(state.text);
    } on Object {
      result = const FailureResult(TtsFailure('음성을 재생하지 못했습니다.'));
    }
    if (_closing || isClosed || revision != _revision) return;
    _endFeedback();
    switch (result) {
      case Success():
        emit(PlaybackState(text: state.text, status: PlaybackStatus.completed));
        _returnTimer = Timer(const Duration(seconds: 2), () {
          if (!_closing && !isClosed && revision == _revision) {
            emit(
              PlaybackState(text: state.text, status: PlaybackStatus.closed),
            );
          }
        });
      case FailureResult(:final failure):
        emit(
          PlaybackState(
            text: state.text,
            status: PlaybackStatus.failed,
            failure: failure,
          ),
        );
    }
  }

  Future<void> _stopTts() => _stopOperation ??= () async {
    try {
      await _tts.stop();
    } on Object {
      /* Route disposal must still complete. */
    }
  }();
  Future<void> stop() async {
    if (_closing || isClosed || state.status == PlaybackStatus.closed) return;
    ++_revision;
    _returnTimer?.cancel();
    _endFeedback();
    emit(PlaybackState(text: state.text, status: PlaybackStatus.closed));
    await _stopTts();
  }

  @override
  Future<void> close() async {
    _closing = true;
    ++_revision;
    _returnTimer?.cancel();
    _endFeedback();
    await _stopTts();
    return super.close();
  }
}
