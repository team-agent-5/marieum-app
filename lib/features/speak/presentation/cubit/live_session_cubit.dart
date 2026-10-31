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
import 'package:marieum_app/features/speak/domain/entities/live_phrase_policy.dart';
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

  /// The segment actually playing; microphone capture continues meanwhile.
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
/// the patient speaks. Valid finals enter playback immediately, in order.
class LiveSessionCubit extends Cubit<LiveSessionState> {
  LiveSessionCubit({
    required this._mic,
    required this._stream,
    required this._repository,
    required this._tts,
    SpeechSegmenter? segmenter,
    DateTime Function()? now,
  }) : _segmenter = segmenter ?? SpeechSegmenter(),
       _now = now ?? DateTime.now,
       super(const LiveSessionState());

  static const historyLength = 32;

  /// How long after the app finishes a sentence it may still come back
  /// through the microphone.
  static const echoTail = Duration(seconds: 1);

  /// Input is ignored this long after the microphone opens while its level
  /// and gain settle; speech in it came out weak or clipped.
  static const warmUp = Duration(milliseconds: 300);

  /// When the server's reading has stopped changing, this much quiet is
  /// enough to end the sentence instead of the segmenter's full pause.
  static const settledPause = Duration(milliseconds: 700);

  /// How long the start of each playback is listened to for the app's own
  /// loudness at the microphone.
  static const echoProbe = Duration(milliseconds: 300);

  /// Voice during playback must be this far above the app's own loudness;
  /// 0.12 of [pcmLevel] is 6 dB.
  static const echoMargin = 0.12;

  final MicStream _mic;
  final LiveStream _stream;
  final UtteranceRepository _repository;
  final PlaybackTtsPort _tts;
  final SpeechSegmenter _segmenter;
  final DateTime Function() _now;

  StreamSubscription<Uint8List>? _input;
  Timer? _clock;
  Future<void> _queue = Future.value();
  int _nextId = 0;
  bool _ended = false;
  LiveUtterance? _active;
  int? _activeId;
  final _lastVoiceAt = <int, DateTime>{};
  final _audioBytes = <int, int>{};
  final _partials = <int, List<Transcription>>{};

  /// Segments where the patient spoke again after the server ended early.
  final _resumed = <int>{};

  /// The latest interim per segment and whether it repeated the one before.
  final _interims = <int, ({String text, bool settled})>{};

  /// A connection opened ahead of time so the next sentence streams at
  /// once instead of waiting for the handshake.
  LiveUtterance? _spare;
  final _sessions = <LiveUtterance>{};
  final _subscriptions = <StreamSubscription<LiveEvent>>{};
  DateTime? _lastInputVoiceAt;
  bool _capturing = false;
  bool _speechBusy = false;
  DateTime? _warmUntil;

  /// Sentences the app spoke, until when their echo may still be heard;
  /// null while still playing.
  final _spoken = <({String text, DateTime? until})>[];

  /// The app's own voice as heard by the microphone, learned from earlier
  /// playbacks.
  double? _echoLevel;
  DateTime? _probeUntil;
  double _probePeak = 0;

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
    _warmUntil = _now().add(warmUp);
  }

  void _listening() {
    _warmUntil = null;
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
    final warmUntil = _warmUntil;
    if (warmUntil != null) {
      if (_now().isBefore(warmUntil)) {
        emit(state.copyWith(levels: levels));
        return;
      }
      _listening();
      _prepareSpare();
    }
    _probeEcho(level);
    final signal = _segmenter.add(chunk, level: level);
    if (_segmenter.hearing ||
        signal is SegmentStarted ||
        level >= state.threshold) {
      _lastInputVoiceAt = _now();
      final id = _activeId;
      if (id != null) {
        _lastVoiceAt[id] = _lastInputVoiceAt!;
        if (_partials.containsKey(id)) _resumed.add(id);
      }
    }
    emit(
      state.copyWith(
        levels: levels,
        hearing: _segmenter.hearing,
        threshold: _segmenter.threshold,
      ),
    );
    switch (signal) {
      case SegmentStarted(:final audio):
        AppLog.speak(
          'live input_level=$level threshold=${_segmenter.threshold}',
        );
        _capturing = true;
        _begin(audio);
      case SegmentContinued(:final audio):
        final id = _activeId;
        if (id == null) {
          _begin(Uint8List(0));
        } else if (_active == null) {
          _openSession(id);
        }
        _addAudio(audio);
        if (id != null &&
            _interims[id]?.settled == true &&
            _segmenter.silence >= settledPause) {
          AppLog.speak('live segment $id settled, ending early');
          _segmenter.reset();
          _capturing = false;
          _finishActive();
        }
      case SegmentEnded(:final audio, :final kept):
        _capturing = false;
        _addAudio(audio);
        kept ? _finishActive() : _drop();
      case null:
        break;
    }
  }

  void _addAudio(Uint8List audio) {
    final id = _activeId;
    if (id == null) return;
    _audioBytes[id] = (_audioBytes[id] ?? 0) + audio.length;
    _active?.add(audio);
  }

  void _begin(Uint8List audio) {
    final id = _nextId++;
    _activeId = id;
    _lastVoiceAt[id] = _lastInputVoiceAt ?? _now();
    _audioBytes[id] = 0;
    AppLog.speak('live segment $id started');
    _openSession(id);
    _addAudio(audio);
  }

  /// One server connection for segment [id]. The server may end it at a
  /// pause while the patient is still talking; its result is then kept and
  /// a new connection carries on, so the sentence is spoken once, whole,
  /// when the app hears the patient stop.
  void _openSession(int id) {
    final spare = _spare;
    _spare = null;
    final utterance = spare != null && !spare.isClosed ? spare : _stream.open();
    _prepareSpare();
    _sessions.add(utterance);
    _active = utterance;
    late final StreamSubscription<LiveEvent> subscription;
    subscription = utterance.events.listen(
      (event) {
        if (_ended || isClosed) return;
        if (event case LiveInterim(:final text)) {
          if (_isEcho(text)) return;
          final previous = _interims[id];
          _interims[id] = (text: text, settled: previous?.text == text);
          _show(id, LiveSegmentStatus.interpreting, _joined(id, text));
          return;
        }
        _sessions.remove(utterance);
        _interims.remove(id);
        if (identical(_active, utterance) && _capturing && _activeId == id) {
          if (event case LiveFinal(:final transcription)) {
            (_partials[id] ??= []).add(transcription);
            _resumed.remove(id);
            _show(id, LiveSegmentStatus.interpreting, _joined(id));
          }
          AppLog.speak('live segment $id server ended early, continuing');
          _active = null;
          _openSession(id);
          return;
        }
        if (identical(_active, utterance)) _active = null;
        _settle(id, event);
      },
      onDone: () {
        _sessions.remove(utterance);
        _subscriptions.remove(subscription);
      },
    );
    _subscriptions.add(subscription);
  }

  void _prepareSpare() {
    if (_ended || isClosed) return;
    final spare = _spare;
    if (spare != null && !spare.isClosed) return;
    _spare = _stream.open();
  }

  String _joined(int id, [String? interim]) => LivePhrasePolicy.displayText(
    [
      for (final partial in _partials[id] ?? const <Transcription>[])
        partial.finalTranscript,
      ?interim,
    ].join(' '),
  );

  /// The segment is over: combines what the server returned for it and
  /// shows, and if clear speaks, the sentence.
  void _settle(int id, LiveEvent event) {
    _resumed.remove(id);
    final pieces = [
      ...?_partials.remove(id),
      if (event case LiveFinal(:final transcription)) transcription,
    ];
    final finalAt = _now();
    final lastVoiceAt = _lastVoiceAt.remove(id) ?? finalAt;
    _audioBytes.remove(id);
    if (pieces.isEmpty) {
      switch (event) {
        case LiveFailed(:final failure):
          _show(id, LiveSegmentStatus.failed, failure.message);
        default:
          _show(id, LiveSegmentStatus.unclear, '');
      }
      return;
    }
    final transcription = _combine(pieces);
    AppLog.speak(
      'live segment $id pieces=${pieces.length} '
      'last_voice=${lastVoiceAt.toIso8601String()} '
      'final=${finalAt.toIso8601String()} '
      'asr_ms=${finalAt.difference(lastVoiceAt).inMilliseconds}',
    );
    if (_isEcho(transcription.finalTranscript)) {
      _remove(id);
      return;
    }
    if (transcription.isLowConfidence ||
        transcription.finalTranscript.contains('\uFFFD')) {
      _show(
        id,
        LiveSegmentStatus.unclear,
        LivePhrasePolicy.displayText(transcription.heard),
      );
      return;
    }
    _show(id, LiveSegmentStatus.done, transcription.finalTranscript);
    final phrase = _LivePlayback(id, transcription, lastVoiceAt, finalAt);
    _queue = _queue.then((_) => _speakAndLog(phrase));
  }

  /// Joins pieces of one sentence; confidence is weighted by length so a
  /// short unclear piece does not sink a long clear one.
  static Transcription _combine(List<Transcription> pieces) {
    if (pieces.length == 1) return pieces.single;
    final texts = [
      for (final piece in pieces)
        if (piece.finalTranscript.trim().isNotEmpty)
          piece.finalTranscript.trim(),
    ];
    var weight = 0;
    var total = 0.0;
    for (final piece in pieces) {
      final length = piece.finalTranscript.trim().length;
      weight += length;
      total += piece.asrConfidence * length;
    }
    return Transcription(
      traceId: pieces.last.traceId,
      finalTranscript: texts.join(' '),
      asrConfidence: weight == 0 ? 0 : total / weight,
    );
  }

  /// Raises the voice threshold while the app speaks: blocked at first,
  /// or at the loudness learned before, until the start of this playback
  /// has been measured.
  void _startEchoGate(DateTime at) {
    _probeUntil = at.add(echoProbe);
    _probePeak = 0;
    final known = _echoLevel;
    _segmenter.playbackFloor = known == null ? 1 : known + echoMargin;
  }

  void _probeEcho(double level) {
    final until = _probeUntil;
    if (until == null) return;
    if (level > _probePeak) _probePeak = level;
    if (_now().isBefore(until)) return;
    _probeUntil = null;
    final known = _echoLevel;
    final echo = known == null ? _probePeak : (known + _probePeak) / 2;
    _echoLevel = echo;
    _segmenter.playbackFloor = echo + echoMargin;
    AppLog.speak('live echo_level=$echo floor=${echo + echoMargin}');
  }

  bool _isEcho(String text) {
    final now = _now();
    _spoken.removeWhere((s) => s.until != null && !s.until!.isAfter(now));
    return _spoken.any((s) => LivePhrasePolicy.isEcho(s.text, text));
  }

  void _finishActive() {
    final id = _activeId;
    if (id == null) return;
    if (_partials.containsKey(id) && !_resumed.contains(id)) {
      // Nothing was said after the server ended early, and the server does
      // not answer a connection without speech; speak what it returned.
      AppLog.speak('live segment $id nothing after early end, settling');
      _active?.cancel();
      _active = null;
      _activeId = null;
      _settle(id, const LiveUnclear());
      return;
    }
    if ((_audioBytes[id] ?? 0) == 0) {
      _active?.cancel();
      _lastVoiceAt.remove(id);
      _audioBytes.remove(id);
    } else {
      _active?.end();
      if (!state.segments.any((s) => s.id == id)) {
        _show(id, LiveSegmentStatus.interpreting, '');
      }
    }
    _active = null;
    _activeId = null;
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
    _lastVoiceAt.remove(id);
    _audioBytes.remove(id);
    _partials.remove(id);
    _interims.remove(id);
    _resumed.remove(id);
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

  Future<void> _speakAndLog(_LivePlayback phrase) async {
    if (_ended || isClosed) return;
    DateTime? playbackAt;
    final result = await _speak(
      phrase.id,
      phrase.transcription.finalTranscript,
      onStarted: (at) {
        playbackAt = at;
        AppLog.speak(
          'live segment ${phrase.id} '
          'last_voice=${phrase.lastVoiceAt.toIso8601String()} '
          'final=${phrase.finalAt.toIso8601String()} '
          'playback=${at.toIso8601String()} '
          'final_to_play_ms=${at.difference(phrase.finalAt).inMilliseconds} '
          'latency_ms=${at.difference(phrase.lastVoiceAt).inMilliseconds}',
        );
      },
    );
    if (_ended || isClosed || result is! Success<void> || playbackAt == null) {
      return;
    }
    final latency = playbackAt!.difference(phrase.lastVoiceAt);
    unawaited(
      _logPlayback(phrase, latency.isNegative ? Duration.zero : latency),
    );
  }

  Future<void> _logPlayback(_LivePlayback phrase, Duration latency) async {
    try {
      final logged = await _repository.bypass(
        phrase.transcription,
        latency: latency,
      );
      if (logged case FailureResult(:final failure)) {
        AppLog.speak(
          'live segment ${phrase.id} not logged ${failure.runtimeType}',
        );
      }
    } on Object catch (error) {
      AppLog.speak('live segment ${phrase.id} log failed ${error.runtimeType}');
    }
  }

  Future<Result<void>> _speak(
    int id,
    String text, {
    void Function(DateTime)? onStarted,
  }) async {
    if (_speechBusy) return const FailureResult(TtsFailure('이미 재생 중이에요.'));
    _speechBusy = true;
    ({String text, DateTime? until})? entry;
    void finishPlayback() {
      final spoken = entry;
      if (spoken == null) return;
      _spoken
        ..remove(spoken)
        ..add((text: spoken.text, until: _now().add(echoTail)));
      entry = null;
      _segmenter.playbackFloor = null;
      _probeUntil = null;
      if (!_ended && !isClosed) emit(state.copyWith(playingId: () => null));
    }

    try {
      return await _tts.speakWithPlayback(
        text,
        onStarted: () {
          if (_ended || isClosed || entry != null) return;
          final at = _now();
          entry = (text: text, until: null);
          _spoken.add(entry!);
          emit(state.copyWith(playingId: () => id));
          _startEchoGate(at);
          onStarted?.call(at);
        },
        onEnded: finishPlayback,
      );
    } on Object {
      return const FailureResult(TtsFailure('음성을 재생하지 못했어요.'));
    } finally {
      finishPlayback();
      _speechBusy = false;
    }
  }

  /// Adds the segment on its first news, or updates it.
  void _show(int id, LiveSegmentStatus status, String text) {
    final visibleText = LivePhrasePolicy.displayText(text);
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
                      ? segment.copyWith(status: status, text: visibleText)
                      : segment,
              ]
            : [
                ...state.segments,
                LiveSegment(
                  id: id,
                  at: _now(),
                  status: status,
                  text: visibleText,
                ),
              ],
      ),
    );
  }

  /// Speaks an earlier sentence again, e.g. when the listener missed it.
  Future<void> replay(int id) async {
    if (_ended || isClosed || _speechBusy) return;
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
    for (final session in _sessions.toList()) {
      session.cancel();
    }
    _sessions.clear();
    for (final subscription in _subscriptions.toList()) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _lastVoiceAt.clear();
    _audioBytes.clear();
    _partials.clear();
    _interims.clear();
    _resumed.clear();
    _spare?.cancel();
    _spare = null;
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

class _LivePlayback {
  const _LivePlayback(
    this.id,
    this.transcription,
    this.lastVoiceAt,
    this.finalAt,
  );
  final int id;
  final Transcription transcription;
  final DateTime lastVoiceAt;
  final DateTime finalAt;
}
