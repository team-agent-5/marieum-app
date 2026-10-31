import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/audio/recorded_audio.dart';
import 'package:marieum_app/core/audio/recorder.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/haptics/haptics.dart';
import 'package:marieum_app/core/log/app_log.dart';
import 'package:marieum_app/features/speak/domain/entities/speak_mode.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:marieum_app/features/speak/domain/repositories/utterance_repository.dart';

enum UtterancePhase {
  idle,
  recording,
  analyzing,
  suggesting,
  reask,
  noMatch,
  failed;

  /// Phases where the main screen must ignore every other control.
  bool get locksScreen => this == recording || this == analyzing;

  /// Phases presented in the bottom sheet.
  bool get usesSheet =>
      this == suggesting || this == reask || this == noMatch || this == failed;
}

sealed class UtteranceEvent extends Equatable {
  const UtteranceEvent();
  @override
  List<Object?> get props => [];
}

/// The main button: starts recording when idle, stops it while recording.
final class UtteranceButtonPressed extends UtteranceEvent {
  const UtteranceButtonPressed(this.mode);
  final SpeakMode mode;
  @override
  List<Object?> get props => [mode];
}

/// Accuracy mode: the button is held while speaking.
final class UtteranceHoldStarted extends UtteranceEvent {
  const UtteranceHoldStarted(this.mode);
  final SpeakMode mode;
  @override
  List<Object?> get props => [mode];
}

/// Releasing the held button ends the recording; a very short hold, such as
/// one interrupted by a permission prompt, is dropped instead.
final class UtteranceHoldEnded extends UtteranceEvent {
  const UtteranceHoldEnded();
}

final class UtteranceCancelPressed extends UtteranceEvent {
  const UtteranceCancelPressed();
}

final class UtteranceCandidateTapped extends UtteranceEvent {
  const UtteranceCandidateTapped(this.candidate);
  final Candidate candidate;
  @override
  List<Object?> get props => [candidate];
}

final class UtteranceConfirmPressed extends UtteranceEvent {
  const UtteranceConfirmPressed();
}

/// "다시 말하기" in the sheet. Rejects the shown candidates, then records again.
final class UtteranceRetryPressed extends UtteranceEvent {
  const UtteranceRetryPressed();
}

/// The sheet was closed by the patient. Not a rejection.
final class UtteranceSheetDismissed extends UtteranceEvent {
  const UtteranceSheetDismissed();
}

final class _Ticked extends UtteranceEvent {
  const _Ticked();
}

final class _LevelChanged extends UtteranceEvent {
  const _LevelChanged(this.level);
  final double level;
}

final class _RecordingEnded extends UtteranceEvent {
  const _RecordingEnded(this.generation, this.result);
  final int generation;
  final Result<RecordedAudio> result;
}

class UtteranceState extends Equatable {
  const UtteranceState({
    this.phase = UtterancePhase.idle,
    this.mode = SpeakMode.precise,
    this.elapsed = Duration.zero,
    this.level = 0,
    this.transcription,
    this.suggestions,
    this.selected,
    this.reaskCount = 0,
    this.spokenText,
    this.notice,
    this.playbackId = 0,
    this.retryMessage,
  });

  final UtterancePhase phase;
  final SpeakMode mode;
  final Duration elapsed;
  final double level;

  final Transcription? transcription;
  final Suggestions? suggestions;
  final Candidate? selected;

  /// Low-confidence attempts in the current speaking session.
  final int reaskCount;

  /// The sentence to play; the playback screen opens when `playbackId` changes.
  final String? spokenText;

  /// Why the flow failed, shown by the failure screen.
  final Failure? notice;
  final int playbackId;
  final String? retryMessage;

  bool get reaskExhausted => reaskCount >= UtteranceBloc.maxReask;

  UtteranceState copyWith({
    UtterancePhase? phase,
    SpeakMode? mode,
    Duration? elapsed,
    double? level,
    Transcription? transcription,
    Suggestions? suggestions,
    Candidate? Function()? selected,
    int? reaskCount,
    String? spokenText,
    String? retryMessage,
  }) => UtteranceState(
    phase: phase ?? this.phase,
    mode: mode ?? this.mode,
    elapsed: elapsed ?? this.elapsed,
    level: level ?? this.level,
    transcription: transcription ?? this.transcription,
    suggestions: suggestions ?? this.suggestions,
    selected: selected == null ? this.selected : selected(),
    reaskCount: reaskCount ?? this.reaskCount,
    spokenText: spokenText ?? this.spokenText,
    playbackId: playbackId,
    retryMessage: retryMessage ?? this.retryMessage,
  );

  @override
  List<Object?> get props => [
    phase,
    mode,
    elapsed,
    level,
    transcription,
    suggestions,
    selected,
    reaskCount,
    spokenText,
    notice,
    playbackId,
    retryMessage,
  ];
}

class UtteranceBloc extends Bloc<UtteranceEvent, UtteranceState> {
  UtteranceBloc({
    required this._repository,
    required this._createRecorder,
    required this._haptics,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       super(const UtteranceState()) {
    on<UtteranceButtonPressed>(_onButton);
    on<UtteranceHoldStarted>((event, emit) async {
      if (state.phase == UtterancePhase.idle) {
        await _startRecording(event.mode, emit, reaskCount: state.reaskCount);
      }
    });
    on<UtteranceHoldEnded>(_onHoldEnded);
    on<UtteranceCancelPressed>(_onCancel);
    on<UtteranceCandidateTapped>(_onCandidate);
    on<UtteranceConfirmPressed>(_onConfirm);
    on<UtteranceRetryPressed>(_onRetry);
    on<UtteranceSheetDismissed>(_onDismissed);
    on<_Ticked>(_onTick);
    on<_LevelChanged>(
      (event, emit) => emit(state.copyWith(level: event.level)),
    );
    on<_RecordingEnded>(_onRecordingEnded);
  }

  static const maxReask = 3;
  static const minHold = Duration(milliseconds: 400);
  static const tick = Duration(milliseconds: 100);

  final UtteranceRepository _repository;
  final Recorder Function() _createRecorder;
  final VoiceHaptics _haptics;
  final DateTime Function() _now;

  /// Bumped whenever the flow is abandoned so late results are ignored.
  int _generation = 0;
  Recorder? _recorder;
  Timer? _ticker;
  StreamSubscription<double>? _levels;
  DateTime? _recordingStartedAt;
  DateTime? _candidatesShownAt;

  Future<void> _onButton(
    UtteranceButtonPressed event,
    Emitter<UtteranceState> emit,
  ) async {
    switch (state.phase) {
      case UtterancePhase.idle:
        await _startRecording(event.mode, emit, reaskCount: state.reaskCount);
      case UtterancePhase.recording:
        await _recorder?.stop().then((_) {}, onError: (Object _) {});
      case _:
        return;
    }
  }

  Future<void> _startRecording(
    SpeakMode mode,
    Emitter<UtteranceState> emit, {
    required int reaskCount,
  }) async {
    final generation = ++_generation;
    final recorder = _createRecorder();
    _recorder = recorder;
    emit(
      UtteranceState(
        phase: UtterancePhase.recording,
        mode: mode,
        reaskCount: reaskCount,
        playbackId: state.playbackId,
      ),
    );
    try {
      await recorder.start();
    } on Object catch (error) {
      await _disposeRecorder();
      if (generation != _generation) return;
      _notify(
        emit,
        error is Failure ? error : const RecordingFailure('녹음을 시작하지 못했어요.'),
        const UtteranceState(),
      );
      return;
    }
    if (generation != _generation) {
      await recorder.dispose();
      return;
    }
    _feedback(VoiceHaptic.recordingStarted);
    AppLog.speak(
      'recording started mode=${mode.name} attempt=${reaskCount + 1}',
    );
    _recordingStartedAt = _now();
    _ticker = Timer.periodic(tick, (_) => add(const _Ticked()));
    _levels = recorder.levels.listen((level) => add(_LevelChanged(level)));
    unawaited(
      recorder.completed.then(
        (audio) => add(_RecordingEnded(generation, Success(audio))),
        onError: (Object error) => add(
          _RecordingEnded(
            generation,
            FailureResult(
              error is Failure
                  ? error
                  : const RecordingFailure('녹음을 끝내지 못했어요.'),
            ),
          ),
        ),
      ),
    );
  }

  void _onTick(_Ticked event, Emitter<UtteranceState> emit) {
    final started = _recordingStartedAt;
    if (state.phase != UtterancePhase.recording || started == null) return;
    final elapsed = _now().difference(started);
    emit(
      state.copyWith(
        elapsed: elapsed > Recorder.maxDuration
            ? Recorder.maxDuration
            : elapsed,
      ),
    );
  }

  Future<void> _onHoldEnded(
    UtteranceHoldEnded event,
    Emitter<UtteranceState> emit,
  ) async {
    if (state.phase != UtterancePhase.recording) return;
    final started = _recordingStartedAt;
    if (started == null || _now().difference(started) < minHold) {
      AppLog.speak('hold too short, dropped');
      ++_generation;
      await _disposeRecorder();
      emit(UtteranceState(mode: state.mode, playbackId: state.playbackId));
      return;
    }
    await _recorder?.stop().then((_) {}, onError: (Object _) {});
  }

  Future<void> _onCancel(
    UtteranceCancelPressed event,
    Emitter<UtteranceState> emit,
  ) async {
    if (!state.phase.locksScreen) return;
    ++_generation;
    await _disposeRecorder();
    emit(UtteranceState(mode: state.mode, playbackId: state.playbackId));
  }

  Future<void> _onRecordingEnded(
    _RecordingEnded event,
    Emitter<UtteranceState> emit,
  ) async {
    if (event.generation != _generation ||
        state.phase != UtterancePhase.recording) {
      return;
    }
    final reachedLimit = state.elapsed >= Recorder.maxDuration - tick;
    await _disposeRecorder();
    _feedback(
      reachedLimit ? VoiceHaptic.recordingLimit : VoiceHaptic.recordingStopped,
    );
    AppLog.speak(
      'recording ended ${state.elapsed.inMilliseconds}ms '
      'limit=$reachedLimit ok=${event.result is Success}',
    );
    switch (event.result) {
      case FailureResult(:final failure):
        _notify(emit, failure, UtteranceState(mode: state.mode));
      case Success(value: final audio):
        emit(state.copyWith(phase: UtterancePhase.analyzing, level: 0));
        await _analyze(audio, event.generation, emit);
    }
  }

  Future<void> _analyze(
    RecordedAudio audio,
    int generation,
    Emitter<UtteranceState> emit,
  ) async {
    final transcribed = await _repository.transcribe(audio);
    if (generation != _generation) return;
    final Transcription transcription;
    switch (transcribed) {
      case FailureResult(:final failure):
        _notify(emit, failure, UtteranceState(mode: state.mode));
        return;
      case Success(:final value):
        transcription = value;
    }
    AppLog.speak(
      'heard "${transcription.finalTranscript}" '
      'confidence=${transcription.asrConfidence} '
      'low=${transcription.isLowConfidence}',
    );
    final suggested = await _repository.suggest(transcription);
    if (generation != _generation) return;
    AppLog.speak(switch (suggested) {
      Success(:final value) => 'candidates ${value.candidates.length}',
      FailureResult(:final failure) => 'suggest failed ${failure.runtimeType}',
    });
    switch (suggested) {
      case Success(:final value) when value.mode == SuggestionMode.retry:
        emit(
          state.copyWith(
            phase: UtterancePhase.reask,
            transcription: transcription,
            suggestions: value,
            reaskCount: state.reaskCount + 1,
            retryMessage: value.retryMessage,
          ),
        );
      case Success(:final value) when value.mode == SuggestionMode.proactive:
        final text = value.verbatim?.text;
        if (text == null) {
          _notify(emit, const ProtocolFailure(), state);
          return;
        }
        emit(
          UtteranceState(
            mode: state.mode,
            transcription: transcription,
            suggestions: value,
            spokenText: text,
            playbackId: state.playbackId + 1,
          ),
        );
      case Success(:final value) when !value.isEmpty:
        _candidatesShownAt = _now();
        emit(
          state.copyWith(
            phase: UtterancePhase.suggesting,
            transcription: transcription,
            suggestions: value,
            selected: () =>
                value.candidates.length == 1 ? value.candidates.single : null,
          ),
        );
      case Success(:final value):
        emit(
          state.copyWith(
            phase: UtterancePhase.noMatch,
            transcription: transcription,
            suggestions: value,
          ),
        );
      case FailureResult(:final failure) when !transcription.isLowConfidence:
        // Without suggestions the patient can still say what was heard.
        AppLog.speak('suggest unavailable ${failure.runtimeType}, heard only');
        final heard = Suggestions(
          traceId: transcription.traceId,
          mode: SuggestionMode.single,
          candidates: [
            Candidate(
              rank: 1,
              text: transcription.finalTranscript,
              score: transcription.asrConfidence,
              reasonDisplay: '방금 들린 그대로',
              source: CandidateSource.asrVerbatim,
            ),
          ],
        );
        _candidatesShownAt = _now();
        emit(
          state.copyWith(
            phase: UtterancePhase.suggesting,
            transcription: transcription,
            suggestions: heard,
            selected: () => heard.candidates.single,
          ),
        );
      case FailureResult(failure: TimeoutFailure()):
        emit(
          state.copyWith(
            phase: UtterancePhase.noMatch,
            transcription: transcription,
          ),
        );
      case FailureResult(:final failure):
        _notify(emit, failure, UtteranceState(mode: state.mode));
    }
  }

  void _onCandidate(
    UtteranceCandidateTapped event,
    Emitter<UtteranceState> emit,
  ) {
    if (state.phase != UtterancePhase.suggesting ||
        !(state.suggestions?.candidates.contains(event.candidate) ?? false)) {
      return;
    }
    _feedback(VoiceHaptic.selected);
    _selectAndSpeak(event.candidate, emit);
  }

  Future<void> _onConfirm(
    UtteranceConfirmPressed event,
    Emitter<UtteranceState> emit,
  ) async {
    final candidate = state.selected;
    if (candidate == null) return;
    _selectAndSpeak(candidate, emit);
  }

  void _selectAndSpeak(Candidate candidate, Emitter<UtteranceState> emit) {
    final transcription = state.transcription;
    final suggestions = state.suggestions;
    if (state.phase != UtterancePhase.suggesting ||
        transcription == null ||
        suggestions == null) {
      return;
    }
    try {
      _repository.logSelected(
        transcription: transcription,
        suggestions: suggestions,
        candidate: candidate,
        latency: _since(_candidatesShownAt),
      );
    } on Object catch (error) {
      AppLog.speak('selection log unavailable ${error.runtimeType}');
    }
    ++_generation;
    _speak(candidate.text, emit);
  }

  /// Hands the sentence to the shared playback screen and ends the flow.
  void _speak(String text, Emitter<UtteranceState> emit) {
    AppLog.speak('play "$text"');
    emit(
      UtteranceState(
        mode: state.mode,
        spokenText: text,
        playbackId: state.playbackId + 1,
      ),
    );
  }

  Future<void> _onRetry(
    UtteranceRetryPressed event,
    Emitter<UtteranceState> emit,
  ) async {
    final transcription = state.transcription;
    final suggestions = state.suggestions;
    switch (state.phase) {
      case UtterancePhase.suggesting
          when transcription != null && suggestions != null:
        _repository.logRejected(
          transcription: transcription,
          suggestions: suggestions,
          latency: _since(_candidatesShownAt),
        );
      case UtterancePhase.reask when !state.reaskExhausted:
      case UtterancePhase.noMatch:
      case UtterancePhase.failed:
        break;
      case _:
        return;
    }
    // The patient holds the main button again to speak.
    ++_generation;
    emit(
      UtteranceState(
        mode: state.mode,
        reaskCount: state.reaskCount,
        playbackId: state.playbackId,
      ),
    );
  }

  Future<void> _onDismissed(
    UtteranceSheetDismissed event,
    Emitter<UtteranceState> emit,
  ) async {
    if (!state.phase.usesSheet) return;
    ++_generation;
    emit(UtteranceState(mode: state.mode, playbackId: state.playbackId));
  }

  /// Shows the failure screen in the sheet; `notice` carries the reason.
  void _notify(
    Emitter<UtteranceState> emit,
    Failure failure,
    UtteranceState next,
  ) {
    AppLog.speak('failed ${failure.runtimeType}: ${failure.message}');
    emit(
      UtteranceState(
        phase: UtterancePhase.failed,
        mode: next.mode,
        notice: failure,
        playbackId: state.playbackId,
      ),
    );
  }

  Duration _since(DateTime? start) =>
      start == null ? Duration.zero : _now().difference(start);

  void _feedback(VoiceHaptic event) =>
      unawaited(_haptics.trigger(event).catchError((Object _) {}));

  Future<void> _disposeRecorder() async {
    _ticker?.cancel();
    _ticker = null;
    await _levels?.cancel();
    _levels = null;
    final recorder = _recorder;
    _recorder = null;
    _recordingStartedAt = null;
    if (recorder != null) {
      try {
        await recorder.dispose();
      } on Object {
        // Disposal failures must not block the flow.
      }
    }
  }

  @override
  Future<void> close() async {
    ++_generation;
    await _disposeRecorder();
    return super.close();
  }
}
