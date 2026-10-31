import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/audio/mic_stream.dart';
import 'package:marieum_app/core/audio/recorded_audio.dart';
import 'package:marieum_app/core/audio/recorder.dart';
import 'package:marieum_app/core/audio/speech_segmenter.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/log/app_log.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:marieum_app/features/speak/domain/repositories/utterance_repository.dart';

enum LiveStatus { starting, listening, failed, closed }

enum LiveSegmentStatus { interpreting, done, unclear, failed }

class LiveSegment extends Equatable {
  const LiveSegment({
    required this.id,
    required this.at,
    this.status = LiveSegmentStatus.interpreting,
    this.text = '',
  });

  final int id;

  /// When the patient finished saying it.
  final DateTime at;
  final LiveSegmentStatus status;

  /// The interpreted sentence, or the failure reason.
  final String text;

  LiveSegment copyWith({LiveSegmentStatus? status, String? text}) =>
      LiveSegment(
        id: id,
        at: at,
        status: status ?? this.status,
        text: text ?? this.text,
      );

  @override
  List<Object?> get props => [id, at, status, text];
}

class LiveSessionState extends Equatable {
  const LiveSessionState({
    this.status = LiveStatus.starting,
    this.levels = const [],
    this.hearing = false,
    this.playingId,
    this.elapsed = Duration.zero,
    this.segments = const [],
    this.failure,
  });

  final LiveStatus status;

  /// Recent input loudness, oldest first, 0 to 1.
  final List<double> levels;

  /// Whether the patient's voice is coming in right now.
  final bool hearing;

  /// The segment being spoken aloud; the microphone is ignored meanwhile.
  final int? playingId;
  final Duration elapsed;
  final List<LiveSegment> segments;
  final Failure? failure;

  bool get playing => playingId != null;

  LiveSessionState copyWith({
    LiveStatus? status,
    List<double>? levels,
    bool? hearing,
    int? Function()? playingId,
    Duration? elapsed,
    List<LiveSegment>? segments,
    Failure? failure,
  }) => LiveSessionState(
    status: status ?? this.status,
    levels: levels ?? this.levels,
    hearing: hearing ?? this.hearing,
    playingId: playingId == null ? this.playingId : playingId(),
    elapsed: elapsed ?? this.elapsed,
    segments: segments ?? this.segments,
    failure: failure ?? this.failure,
  );

  @override
  List<Object?> get props => [
    status,
    levels,
    hearing,
    playingId,
    elapsed,
    segments,
    failure,
  ];
}

/// Live mode: keeps listening, sends each pause-delimited segment to the
/// server for interpretation, shows the result as soon as it returns and
/// speaks it. Segments are interpreted and spoken in order.
class LiveSessionCubit extends Cubit<LiveSessionState> {
  LiveSessionCubit({
    required this._mic,
    required this._repository,
    required this._tts,
    SpeechSegmenter? segmenter,
    DateTime Function()? now,
  }) : _segmenter = segmenter ?? SpeechSegmenter(),
       _now = now ?? DateTime.now,
       super(const LiveSessionState());

  static const historyLength = 32;

  final MicStream _mic;
  final UtteranceRepository _repository;
  final TtsPort _tts;
  final SpeechSegmenter _segmenter;
  final DateTime Function() _now;

  StreamSubscription<Uint8List>? _input;
  Timer? _clock;
  Future<void> _queue = Future.value();
  int _nextId = 0;
  bool _ended = false;

  Future<void> start() async {
    if (state.status != LiveStatus.starting) return;
    try {
      final stream = await _mic.start();
      if (_ended) {
        await _mic.stop();
        return;
      }
      _input = stream.listen(_onChunk);
    } on Object catch (error) {
      if (_ended) return;
      final failure = error is Failure
          ? error
          : const RecordingFailure('마이크를 열지 못했어요.');
      AppLog.speak('live failed to start ${failure.runtimeType}');
      emit(state.copyWith(status: LiveStatus.failed, failure: failure));
      return;
    }
    final startedAt = _now();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isClosed) {
        emit(state.copyWith(elapsed: _now().difference(startedAt)));
      }
    });
    AppLog.speak('live listening');
    emit(state.copyWith(status: LiveStatus.listening));
  }

  void _onChunk(Uint8List chunk) {
    if (_ended || isClosed) return;
    final level = pcmLevel(chunk);
    final levels = [...state.levels, if (state.playing) 0.0 else level];
    if (levels.length > historyLength) levels.removeAt(0);
    if (state.playing) {
      // The app's own voice must not be heard as the patient's.
      _segmenter.reset();
      emit(state.copyWith(levels: levels, hearing: false));
      return;
    }
    final segment = _segmenter.add(chunk, level: level);
    emit(state.copyWith(levels: levels, hearing: _segmenter.hearing));
    if (segment != null) _enqueue(segment);
  }

  void _enqueue(Uint8List pcm) {
    final id = _nextId++;
    final endedAt = _now();
    AppLog.speak('live segment $id ${pcm.length}B');
    emit(
      state.copyWith(
        segments: [
          ...state.segments,
          LiveSegment(id: id, at: endedAt),
        ],
      ),
    );
    _queue = _queue.then((_) => _interpret(id, pcm, endedAt));
  }

  Future<void> _interpret(int id, Uint8List pcm, DateTime endedAt) async {
    if (_ended || isClosed) return;
    final transcribed = await _repository.transcribe(encodePcmWav(pcm));
    if (_ended || isClosed) return;
    final Transcription transcription;
    switch (transcribed) {
      case FailureResult(:final failure):
        _update(id, LiveSegmentStatus.failed, failure.message);
        return;
      case Success(:final value):
        transcription = value;
    }
    if (transcription.isLowConfidence) {
      _update(id, LiveSegmentStatus.unclear, transcription.heard);
      return;
    }
    final spoken = await _repository.bypass(
      transcription,
      latency: _now().difference(endedAt),
    );
    if (_ended || isClosed) return;
    switch (spoken) {
      case FailureResult(failure: ValidationFailure()):
        _update(id, LiveSegmentStatus.unclear, transcription.heard);
      case FailureResult(:final failure):
        _update(id, LiveSegmentStatus.failed, failure.message);
      case Success(:final value):
        _update(id, LiveSegmentStatus.done, value);
        await _speak(id, value);
    }
  }

  Future<void> _speak(int id, String text) async {
    emit(state.copyWith(playingId: () => id, hearing: false));
    await _tts.speak(text);
    if (_ended || isClosed) return;
    emit(state.copyWith(playingId: () => null));
  }

  void _update(int id, LiveSegmentStatus status, String text) {
    AppLog.speak('live segment $id ${status.name} "$text"');
    emit(
      state.copyWith(
        segments: [
          for (final segment in state.segments)
            segment.id == id
                ? segment.copyWith(status: status, text: text)
                : segment,
        ],
      ),
    );
  }

  /// Speaks an earlier sentence again, e.g. when the listener missed it.
  Future<void> replay(int id) async {
    if (_ended || isClosed || state.playing) return;
    final segment = state.segments.where((s) => s.id == id).firstOrNull;
    if (segment == null || segment.status != LiveSegmentStatus.done) return;
    AppLog.speak('live replay $id');
    await _speak(id, segment.text);
  }

  /// Ends the session; segments still on their way are dropped.
  Future<void> stop() async {
    if (_ended) return;
    _ended = true;
    _clock?.cancel();
    await _input?.cancel();
    _input = null;
    await _mic.stop();
    await _tts.stop();
    if (!isClosed) {
      emit(state.copyWith(status: LiveStatus.closed, playingId: () => null));
    }
  }

  @override
  Future<void> close() async {
    await stop();
    await _mic.dispose();
    return super.close();
  }
}
