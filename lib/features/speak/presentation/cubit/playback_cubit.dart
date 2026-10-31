import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/haptics/haptics.dart';
import 'package:marieum_app/core/log/app_log.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:marieum_app/features/speak/domain/repositories/utterance_repository.dart';

enum PlaybackStatus { initial, playing, completed, failed, closed }

class PlaybackState extends Equatable {
  const PlaybackState({
    required this.text,
    this.status = PlaybackStatus.initial,
    this.failure,
    this.suggestion,
    this.suggestionPending = false,
  });
  final String text;
  final PlaybackStatus status;
  final Failure? failure;
  final ProactiveSuggestion? suggestion;
  final bool suggestionPending;
  @override
  List<Object?> get props => [
    text,
    status,
    failure,
    suggestion,
    suggestionPending,
  ];
}

class PlaybackCubit extends Cubit<PlaybackState> {
  PlaybackCubit({
    required PlaybackRequest request,
    required this._tts,
    required this._haptics,
    this.repository,
    DateTime Function()? now,
  }) : _request = request,
       _now = now ?? DateTime.now,
       super(PlaybackState(text: request.text));

  static const returnDelay = Duration(seconds: 2);
  static const suggestionDelay = Duration(seconds: 3);

  final TtsPort _tts;
  final VoiceHaptics _haptics;
  final PlaybackRequest _request;
  final UtteranceRepository? repository;
  final DateTime Function() _now;
  Timer? _returnTimer;
  Timer? _suggestionTimer;
  DateTime? _suggestionShownAt;

  /// A proactive playback is logged once, as the sentence that was kept.
  bool _choiceLogged = false;
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
    final suggestion = _request.suggestions?.proactiveSuggestion;
    if (suggestion != null) {
      _suggestionShownAt = _now();
      _suggestionTimer = Timer(suggestionDelay, declineSuggestion);
    } else {
      _logVerbatim();
    }
    await _playText(state.text, suggestionPending: suggestion != null);
  }

  void _update(
    PlaybackStatus status, {
    String? text,
    Failure? failure,
    bool? suggestionPending,
  }) {
    emit(
      PlaybackState(
        text: text ?? state.text,
        status: status,
        failure: failure,
        suggestion: _request.suggestions?.proactiveSuggestion,
        suggestionPending: suggestionPending ?? state.suggestionPending,
      ),
    );
  }

  Future<void> _playText(String text, {bool? suggestionPending}) async {
    final revision = ++_revision;
    _endFeedbackSent = false;
    _update(
      PlaybackStatus.playing,
      text: text,
      suggestionPending: suggestionPending,
    );
    unawaited(_feedback(VoiceHaptic.playbackStarted));
    Result<void> result;
    try {
      result = await _tts.speak(text);
    } on Object {
      result = const FailureResult(TtsFailure('음성을 재생하지 못했습니다.'));
    }
    if (_closing || isClosed || revision != _revision) return;
    _endFeedback();
    switch (result) {
      case Success():
        _update(PlaybackStatus.completed);
        if (!state.suggestionPending) _scheduleReturn();
      case FailureResult(:final failure):
        _update(PlaybackStatus.failed, failure: failure);
    }
  }

  void _scheduleReturn() {
    _returnTimer?.cancel();
    _returnTimer = Timer(returnDelay, () {
      if (!_closing && !isClosed && !state.suggestionPending) {
        _update(PlaybackStatus.closed);
      }
    });
  }

  void declineSuggestion() {
    if (_closing || isClosed || !state.suggestionPending) return;
    _suggestionTimer?.cancel();
    _logVerbatim();
    _update(state.status, failure: state.failure, suggestionPending: false);
    if (state.status == PlaybackStatus.completed) _scheduleReturn();
  }

  /// The heard sentence, read at once in proactive mode, was what the
  /// patient said unless they took the suggestion instead.
  void _logVerbatim() {
    final suggestions = _request.suggestions;
    final verbatim = suggestions?.verbatim;
    if (suggestions?.mode != SuggestionMode.proactive || verbatim == null) {
      return;
    }
    _logChoice(verbatim);
  }

  void _logChoice(Candidate candidate) {
    final transcription = _request.transcription;
    final suggestions = _request.suggestions;
    if (_choiceLogged || transcription == null || suggestions == null) return;
    _choiceLogged = true;
    try {
      repository?.logSelected(
        transcription: transcription,
        suggestions: suggestions,
        candidate: candidate,
        latency: _now().difference(_suggestionShownAt ?? _now()),
      );
    } on Object catch (error) {
      AppLog.speak('proactive log unavailable ${error.runtimeType}');
    }
  }

  Future<void> acceptSuggestion() async {
    final suggestion = state.suggestion;
    if (_closing ||
        isClosed ||
        !state.suggestionPending ||
        suggestion == null) {
      return;
    }
    _suggestionTimer?.cancel();
    _returnTimer?.cancel();
    ++_revision;
    final shouldStop = state.status == PlaybackStatus.playing;
    _update(state.status, failure: state.failure, suggestionPending: false);
    _logChoice(suggestion.candidate);
    if (shouldStop) {
      await _stopTts();
      _endFeedback();
    }
    if (_closing || isClosed || state.status == PlaybackStatus.closed) return;
    _stopOperation = null;
    await _playText(suggestion.candidate.text, suggestionPending: false);
  }

  Future<void> retry() async {
    if (state.status != PlaybackStatus.failed || _closing || isClosed) return;
    await _playText(state.text);
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
    _suggestionTimer?.cancel();
    _endFeedback();
    emit(PlaybackState(text: state.text, status: PlaybackStatus.closed));
    await _stopTts();
  }

  @override
  Future<void> close() async {
    // Leaving before answering the suggestion keeps the heard sentence.
    if (state.suggestionPending) _logVerbatim();
    _closing = true;
    ++_revision;
    _returnTimer?.cancel();
    _suggestionTimer?.cancel();
    _endFeedback();
    await _stopTts();
    return super.close();
  }
}
