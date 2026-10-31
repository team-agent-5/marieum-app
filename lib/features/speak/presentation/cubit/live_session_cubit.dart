import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/audio/mic_stream.dart';
import 'package:marieum_app/core/audio/recorder.dart';
import 'package:marieum_app/core/audio/speech_segmenter.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/log/app_log.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:marieum_app/features/speak/domain/repositories/live_stream.dart';
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

  /// When the sentence first showed up.
  final DateTime at;
  final LiveSegmentStatus status;

  /// The sentence understood so far while interpreting, then the final
  /// sentence or the failure reason.
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
    this.threshold = SpeechSegmenter.defaultThreshold,
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

  /// The level that currently counts as voice, following the room noise.
  final double threshold;

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
    double? threshold,
    int? Function()? playingId,
    Duration? elapsed,
    List<LiveSegment>? segments,
    Failure? failure,
  }) => LiveSessionState(
    status: status ?? this.status,
    levels: levels ?? this.levels,
    hearing: hearing ?? this.hearing,
    threshold: threshold ?? this.threshold,
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
    threshold,
    playingId,
    elapsed,
    segments,
    failure,
  ];
}

/// Live mode: keeps listening and streams each utterance to the server as
/// the patient speaks, showing what it understands so far. Each final
/// sentence is spoken as soon as it arrives, without pausing the
/// microphone, and logged once it has been heard.
class LiveSessionCubit extends Cubit<LiveSessionState> {
  LiveSessionCubit({
    required this._mic,
    required this._stream,
    required this._repository,
    required this._tts,
    this._prefetchSpeech,
    SpeechSegmenter? segmenter,
    DateTime Function()? now,
  }) : _segmenter = segmenter ?? SpeechSegmenter(),
       _now = now ?? DateTime.now,
       super(const LiveSessionState());

  static const historyLength = 32;

  /// How long after the app finishes a sentence it may still come back
  /// through the microphone.
  static const echoTail = Duration(milliseconds: 1500);

  final MicStream _mic;
  final LiveStream _stream;
  final UtteranceRepository _repository;
  final TtsPort _tts;

  /// Lets the voice prepare a sentence while its final is still on the way.
  final void Function(String)? _prefetchSpeech;
  final SpeechSegmenter _segmenter;
  final DateTime Function() _now;

  StreamSubscription<Uint8List>? _input;
  Timer? _clock;
  Future<void> _queue = Future.value();
  int _nextId = 0;
  bool _ended = false;
  LiveUtterance? _active;
  int? _activeId;
  final _endedAt = <int, DateTime>{};
  final _interim = <int, String>{};

  /// Sentences the app spoke, until when their echo may still be heard;
  /// null while still playing.
  final _spoken = <({String text, DateTime? until})>[];

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
    final levels = [...state.levels, level];
    if (levels.length > historyLength) levels.removeAt(0);
    final signal = _segmenter.add(chunk, level: level);
    emit(
      state.copyWith(
        levels: levels,
        hearing: _segmenter.hearing,
        threshold: _segmenter.threshold,
      ),
    );
    switch (signal) {
      case SegmentStarted(:final audio):
        _begin(audio);
      case SegmentContinued(:final audio):
        _active?.add(audio);
      case SegmentEnded(:final audio, :final kept):
        _active?.add(audio);
        kept ? _finishActive() : _drop();
      case null:
        break;
    }
  }

  void _begin(Uint8List audio) {
    final id = _nextId++;
    final utterance = _stream.open()..add(audio);
    _active = utterance;
    _activeId = id;
    AppLog.speak('live segment $id started');
    utterance.events.listen(
      (event) {
        if (_ended || isClosed) return;
        switch (event) {
          case LiveInterim(:final text):
            if (_isEcho(text)) return;
            _interim[id] = text;
            _show(id, LiveSegmentStatus.interpreting, text);
          case LiveFinal(:final transcription):
            _interim.remove(id);
            final endedAt = _endedAt.remove(id) ?? _now();
            if (_isEcho(transcription.finalTranscript)) {
              AppLog.speak("live segment $id was the app's own voice");
              _remove(id);
              return;
            }
            if (transcription.isLowConfidence) {
              _show(id, LiveSegmentStatus.unclear, transcription.heard);
              return;
            }
            _show(id, LiveSegmentStatus.done, transcription.finalTranscript);
            final latency = _now().difference(endedAt);
            _queue = _queue.then(
              (_) => _speakAndLog(id, transcription, latency),
            );
          case LiveUnclear():
            _interim.remove(id);
            _show(id, LiveSegmentStatus.unclear, '');
          case LiveFailed(:final failure):
            _interim.remove(id);
            _show(id, LiveSegmentStatus.failed, failure.message);
        }
      },
    );
  }

  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'[\s.,!?~…]'), '');

  /// Whether [text] is the app's own recent sentence coming back through
  /// the microphone rather than the patient speaking.
  bool _isEcho(String text) {
    final now = _now();
    _spoken.removeWhere((s) => s.until != null && s.until!.isBefore(now));
    final heard = _normalize(text);
    if (heard.isEmpty) return false;
    return _spoken.any((s) => s.text.contains(heard));
  }

  void _finishActive() {
    final id = _activeId;
    if (id == null) return;
    _endedAt[id] = _now();
    final guess = _interim[id];
    if (guess != null) _prefetchSpeech?.call(guess);
    _active?.end();
    _active = null;
    _activeId = null;
    if (!state.segments.any((s) => s.id == id)) {
      _show(id, LiveSegmentStatus.interpreting, '');
    }
  }

  /// Abandons the utterance in progress, e.g. a click too short to be speech.
  void _drop() {
    _segmenter.reset();
    final id = _activeId;
    if (id == null) return;
    AppLog.speak('live segment $id dropped');
    _active?.cancel();
    _active = null;
    _activeId = null;
    _endedAt.remove(id);
    _interim.remove(id);
    _remove(id);
  }

  void _remove(int id) {
    if (!state.segments.any((s) => s.id == id)) return;
    emit(
      state.copyWith(
        segments: [
          for (final s in state.segments)
            if (s.id != id) s,
        ],
      ),
    );
  }

  Future<void> _speakAndLog(
    int id,
    Transcription transcription,
    Duration latency,
  ) async {
    if (_ended || isClosed) return;
    await _speak(id, transcription.finalTranscript);
    if (_ended || isClosed) return;
    unawaited(
      _repository.bypass(transcription, latency: latency).then((logged) {
        if (logged case FailureResult(:final failure)) {
          AppLog.speak('live segment $id not logged ${failure.runtimeType}');
        }
      }),
    );
  }

  Future<void> _speak(int id, String text) async {
    final entry = (text: _normalize(text), until: null);
    _spoken.add(entry);
    emit(state.copyWith(playingId: () => id));
    await _tts.speak(text);
    _spoken
      ..remove(entry)
      ..add((text: entry.text, until: _now().add(echoTail)));
    if (_ended || isClosed) return;
    emit(state.copyWith(playingId: () => null));
  }

  /// Adds the segment on its first news, or updates it.
  void _show(int id, LiveSegmentStatus status, String text) {
    if (status != LiveSegmentStatus.interpreting) {
      AppLog.speak('live segment $id ${status.name} "$text"');
    }
    final known = state.segments.any((s) => s.id == id);
    emit(
      state.copyWith(
        segments: known
            ? [
                for (final segment in state.segments)
                  segment.id == id
                      ? segment.copyWith(status: status, text: text)
                      : segment,
              ]
            : [
                ...state.segments,
                LiveSegment(id: id, at: _now(), status: status, text: text),
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

  /// Ends the session; utterances still on their way are dropped.
  Future<void> stop() async {
    if (_ended) return;
    _ended = true;
    _clock?.cancel();
    _active?.cancel();
    _active = null;
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
