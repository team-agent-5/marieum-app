import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/audio/mic_stream.dart';
import 'package:marieum_app/core/audio/recorder.dart';
import 'package:marieum_app/core/audio/speech_pace.dart';
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
    this.stable = 0,
  });

  final int id;

  /// When the sentence first showed up.
  final DateTime at;
  final LiveSegmentStatus status;

  /// The sentence understood so far while interpreting, then the final
  /// sentence or the failure reason.
  final String text;

  /// How much of [text] the server has stopped changing while interpreting.
  final int stable;

  LiveSegment copyWith({
    LiveSegmentStatus? status,
    String? text,
    int? stable,
  }) => LiveSegment(
    id: id,
    at: at,
    status: status ?? this.status,
    text: text ?? this.text,
    stable: stable ?? this.stable,
  );

  @override
  List<Object?> get props => [id, at, status, text, stable];
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
    this.reconnecting = false,
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

  /// The server cannot reach its recognizer for the moment.
  final bool reconnecting;

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
    bool? reconnecting,
  }) => LiveSessionState(
    status: status ?? this.status,
    levels: levels ?? this.levels,
    hearing: hearing ?? this.hearing,
    threshold: threshold ?? this.threshold,
    playingId: playingId == null ? this.playingId : playingId(),
    elapsed: elapsed ?? this.elapsed,
    segments: segments ?? this.segments,
    failure: failure ?? this.failure,
    reconnecting: reconnecting ?? this.reconnecting,
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
    reconnecting,
  ];
}

/// Live mode: keeps the microphone open and streams everything over one
/// connection for the whole session. The server's recognizer decides where
/// each sentence ends; every final it sends is spoken at once and logged
/// once it has been heard.
class LiveSessionCubit extends Cubit<LiveSessionState> {
  LiveSessionCubit({
    required this._mic,
    required this._stream,
    required this._repository,
    required this._tts,
    this.muteWhileSpeaking = false,
    this._pace,
    SpeechSegmenter? segmenter,
    DateTime Function()? now,
  }) : _levels = segmenter ?? SpeechSegmenter(),
       _now = now ?? DateTime.now,
       super(const LiveSessionState());

  static const historyLength = 32;

  /// How long after the app finishes a sentence it may still come back
  /// through the microphone.
  static const echoTail = Duration(seconds: 1);

  /// Input is not sent this long after the microphone opens while its
  /// level and gain settle; speech in it came out weak or clipped.
  static const warmUp = Duration(milliseconds: 300);

  /// Below this a sentence is not spoken aloud: in live mode nobody checks
  /// it first, and low readings were mostly wrong sentences.
  static const speakConfidence = 0.6;

  /// How long after the app's voice ends its echo is still kept out.
  static const muteTail = Duration(milliseconds: 300);

  /// Without a pace setting, how long an unfinished sentence waits for the
  /// rest of it.
  static const defaultContinuationWait = Duration(milliseconds: 1200);

  /// How long an unfinished sentence waits once the patient goes on, for
  /// the recognizer to close the rest.
  static const continuationLimit = Duration(seconds: 8);

  /// Most pieces joined into one sentence.
  static const maxPieces = 3;

  /// The first words reach the screen about this long after speech starts.
  static const _interimLag = Duration(milliseconds: 500);

  /// A sentence needs at least this much voice on the microphone. The
  /// recognizer makes up sentences out of room noise and silence.
  static const minVoice = Duration(milliseconds: 300);

  /// Input this far below the voice threshold still counts as the
  /// patient's voice here, so quiet speakers are not cut.
  static const _voiceSlack = 0.08;

  /// The lowest level that counts as voice, about -40 dBFS.
  static const _voiceFloor = 0.2;

  /// Sends silence instead of the microphone while the app's voice plays.
  /// Android cannot cancel the app's own media playback from the input, so
  /// without this the server hears the app and the sentence is spoken over
  /// and over.
  final bool muteWhileSpeaking;

  final MicStream _mic;
  final LiveStream _stream;
  final UtteranceRepository _repository;
  final PlaybackTtsPort _tts;
  final SpeechPaceTracker? _pace;

  /// Only tracks the room's loudness for the input display; sentences are
  /// split by the server.
  final SpeechSegmenter _levels;
  final DateTime Function() _now;

  StreamSubscription<Uint8List>? _input;
  LiveConversation? _conversation;
  StreamSubscription<LiveEvent>? _events;
  Timer? _clock;
  final _pending = <_LivePlayback>[];
  bool _draining = false;
  int _nextId = 0;
  bool _ended = false;
  bool _speechBusy = false;
  DateTime? _mutedUntil;

  /// Whether the app's voice is actually coming out of the speaker, as
  /// opposed to still being prepared.
  bool _sounding = false;
  DateTime? _warmUntil;

  /// The sentence the server is reading now, shown as it changes.
  int? _currentId;
  DateTime? _lastVoiceAt;

  String _lastInterim = '';

  /// When each sentence's first words came in.
  final _startedAt = <int, DateTime>{};

  /// A finished but open-ended sentence kept back for the rest of it.
  _LivePlayback? _held;
  Timer? _holdTimer;

  /// When the microphone picked up voice, newest last, for [minVoice].
  final _voiced = <({DateTime at, int ms})>[];

  /// Whether a connection problem is already on screen.
  bool _showingFailure = false;

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
    _warmUntil = _now().add(warmUp);
  }

  void _listening() {
    _warmUntil = null;
    final conversation = _conversation = _stream.connect();
    _events = conversation.events.listen(_onEvent);
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
    }
    _levels.add(chunk, level: level);
    if (_levels.hearing) _lastVoiceAt = _now();
    _noteVoice(chunk, level);
    final mutedUntil = _mutedUntil;
    final muted =
        muteWhileSpeaking &&
        (_sounding || (mutedUntil != null && _now().isBefore(mutedUntil)));
    _conversation?.add(muted ? Uint8List(chunk.length) : chunk);
    emit(
      state.copyWith(
        levels: levels,
        hearing: _levels.hearing,
        threshold: _levels.threshold,
      ),
    );
  }

  void _onEvent(LiveEvent event) {
    if (_ended || isClosed) return;
    switch (event) {
      case LiveInterim(:final text):
        if (_isEcho(text)) return;
        _recovered();
        // The server only reads what it hears, so this is also the latest
        // sign of the patient's voice when the input level stays low.
        _lastVoiceAt = _now();
        if (_currentId == null &&
            _voiceSince(_now().subtract(const Duration(seconds: 3))) <
                const Duration(milliseconds: 100)) {
          // Nothing reached the microphone; likely made up from noise.
          return;
        }
        final held = _held;
        final id = _currentId ??= held?.id ?? _nextId++;
        _startedAt.putIfAbsent(id, () => _now().subtract(_interimLag));
        final shown = LivePhrasePolicy.displayText(text);
        final stable = LivePhrasePolicy.stablePrefix(_lastInterim, shown);
        _lastInterim = shown;
        if (held != null && id == held.id) {
          // The patient went on; the open sentence waits for the rest.
          _holdFor(continuationLimit);
          _show(
            id,
            LiveSegmentStatus.interpreting,
            '${held.text} $shown',
            stable: held.text.length + 1 + stable,
          );
          return;
        }
        _show(id, LiveSegmentStatus.interpreting, shown, stable: stable);
      case LiveFinal(:final transcription):
        final id = _currentId ?? _nextId++;
        _currentId = null;
        _lastInterim = '';
        _recovered();
        _settle(id, transcription);
      case LiveUpstreamDown():
        AppLog.speak('live recognizer unavailable');
        if (!state.reconnecting) emit(state.copyWith(reconnecting: true));
      case LiveUnclear():
        final id = _currentId;
        _currentId = null;
        _lastInterim = '';
        final held = _held;
        if (held != null) {
          _releaseHeld();
          if (id == held.id) return;
        }
        // Silence the server closed off is not worth a line.
        if (id != null) _show(id, LiveSegmentStatus.unclear, '');
      case LiveFailed(:final failure, :final recovering):
        if (!recovering) {
          emit(state.copyWith(status: LiveStatus.failed, failure: failure));
          return;
        }
        _releaseHeld();
        if (_showingFailure) return;
        _showingFailure = true;
        final id = _currentId ?? _nextId++;
        _currentId = null;
        _show(id, LiveSegmentStatus.failed, failure.message);
    }
  }

  void _recovered() {
    _showingFailure = false;
    if (state.reconnecting) emit(state.copyWith(reconnecting: false));
  }

  void _settle(int id, Transcription transcription) {
    final finalAt = _now();
    final lastVoiceAt = _lastVoiceAt ?? finalAt;
    _lastVoiceAt = null;
    AppLog.speak(
      'live segment $id last_voice=${lastVoiceAt.toIso8601String()} '
      'final=${finalAt.toIso8601String()} '
      'asr_ms=${finalAt.difference(lastVoiceAt).inMilliseconds}',
    );
    final heldNow = _held;
    final from =
        (_startedAt[id] ?? finalAt.subtract(const Duration(seconds: 10)))
            .subtract(const Duration(milliseconds: 1500));
    if (_voiceSince(from) < minVoice) {
      AppLog.speak('live segment $id no voice on the microphone, dropped');
      if (heldNow != null && id == heldNow.id) {
        _show(
          id,
          LiveSegmentStatus.interpreting,
          heldNow.text,
          stable: heldNow.text.length,
        );
      } else {
        _startedAt.remove(id);
        _remove(id);
      }
      return;
    }
    final text = transcription.finalTranscript;
    final weak =
        transcription.isLowConfidence ||
        transcription.asrConfidence < speakConfidence ||
        text.contains('�');
    final echo = _isEcho(text);
    // A scrap heard right after the app spoke is most likely its own voice.
    final scrap = _nearOwnVoice && (LivePhrasePolicy.isFragment(text) || weak);
    final runaway = LivePhrasePolicy.isRunaway(text);
    if (echo || scrap || runaway || weak) {
      // What was kept back is said as it is; this piece gets its own line.
      final held = _held;
      var own = id;
      if (held != null) {
        _releaseHeld();
        if (id == held.id) own = _nextId++;
      }
      _startedAt.remove(id);
      if (echo || scrap) {
        AppLog.speak(
          "live segment $own ${echo ? "was the app's own voice" : 'scrap'}",
        );
        _remove(own);
      } else if (runaway) {
        AppLog.speak('live segment $own runaway text, not spoken');
        _show(own, LiveSegmentStatus.unclear, '');
      } else {
        _show(
          own,
          LiveSegmentStatus.unclear,
          LivePhrasePolicy.displayText(transcription.heard),
        );
      }
      return;
    }
    var phrase = _LivePlayback(id, transcription, lastVoiceAt, finalAt);
    final held = _held;
    if (held != null) {
      _held = null;
      _holdTimer?.cancel();
      phrase = held.join(phrase);
      AppLog.speak('live segment ${phrase.id} joined ${phrase.pieces} pieces');
    }
    if (LivePhrasePolicy.isUnfinished(phrase.text) &&
        phrase.pieces < maxPieces) {
      _held = phrase;
      _holdFor(_pace?.continuationWait ?? defaultContinuationWait);
      AppLog.speak('live segment ${phrase.id} open-ended, waiting');
      _show(
        phrase.id,
        LiveSegmentStatus.interpreting,
        phrase.text,
        stable: phrase.text.length,
      );
      return;
    }
    _finish(phrase);
  }

  void _noteVoice(Uint8List chunk, double level) {
    final now = _now();
    _voiced.removeWhere(
      (v) => now.difference(v.at) > const Duration(seconds: 30),
    );
    // The app's own voice is not the patient's.
    if (_sounding) return;
    final bar = _levels.threshold - _voiceSlack;
    if (level < (bar > _voiceFloor ? bar : _voiceFloor)) return;
    _voiced.add((at: now, ms: chunk.length * 1000 ~/ Recorder.bytesPerSecond));
  }

  Duration _voiceSince(DateTime from) => Duration(
    milliseconds: _voiced
        .where((v) => v.at.isAfter(from))
        .fold(0, (sum, v) => sum + v.ms),
  );

  /// Whether the app is speaking or has just stopped.
  bool get _nearOwnVoice {
    final now = _now();
    return _sounding ||
        _spoken.any((s) => s.until == null || s.until!.isAfter(now));
  }

  void _holdFor(Duration wait) {
    _holdTimer?.cancel();
    _holdTimer = Timer(wait, _releaseHeld);
  }

  /// Says the kept-back sentence as it is.
  void _releaseHeld() {
    final held = _held;
    if (held == null) return;
    _held = null;
    _holdTimer?.cancel();
    if (_ended || isClosed) return;
    if (_currentId == held.id) {
      // Whatever the patient says next starts a line of its own.
      _currentId = null;
      _lastInterim = '';
    }
    _finish(held);
  }

  void _finish(_LivePlayback phrase) {
    final started = _startedAt.remove(phrase.id);
    if (started != null) {
      _pace?.observe(phrase.text, phrase.lastVoiceAt.difference(started));
    }
    _show(phrase.id, LiveSegmentStatus.done, phrase.text);
    _pending.add(phrase);
    unawaited(_drain());
  }

  /// Speaks waiting sentences. Those that arrived while another was playing
  /// are read together in one go, so a patient who keeps talking is not
  /// held up sentence by sentence.
  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty && !_ended && !isClosed) {
        final batch = [..._pending];
        _pending.clear();
        await _speakAndLog(batch);
      }
    } finally {
      _draining = false;
    }
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

  bool _isEcho(String text) {
    final now = _now();
    _spoken.removeWhere((s) => s.until != null && !s.until!.isAfter(now));
    return _spoken.any((s) => LivePhrasePolicy.isEcho(s.text, text));
  }

  Future<void> _speakAndLog(List<_LivePlayback> batch) async {
    if (_ended || isClosed) return;
    DateTime? playbackAt;
    final result = await _speak(
      batch.last.id,
      batch.map((p) => p.text).join(' '),
      onStarted: (at) {
        playbackAt = at;
        for (final phrase in batch) {
          AppLog.speak(
            'live segment ${phrase.id} batch=${batch.length} '
            'final_to_play_ms=${at.difference(phrase.finalAt).inMilliseconds} '
            'latency_ms=${at.difference(phrase.lastVoiceAt).inMilliseconds}',
          );
        }
      },
    );
    if (_ended || isClosed || result is! Success<void> || playbackAt == null) {
      return;
    }
    for (final phrase in batch) {
      final latency = playbackAt!.difference(phrase.lastVoiceAt);
      unawaited(
        _logPlayback(phrase, latency.isNegative ? Duration.zero : latency),
      );
    }
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
          _sounding = true;
          onStarted?.call(at);
        },
        onEnded: finishPlayback,
      );
    } on Object {
      return const FailureResult(TtsFailure('음성을 재생하지 못했어요.'));
    } finally {
      finishPlayback();
      _speechBusy = false;
      if (_sounding) _mutedUntil = _now().add(muteTail);
      _sounding = false;
    }
  }

  /// Adds the segment on its first news, or updates it.
  void _show(
    int id,
    LiveSegmentStatus status,
    String text, {
    int stable = 0,
  }) {
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
                      ? segment.copyWith(
                          status: status,
                          text: visibleText,
                          stable: stable,
                        )
                      : segment,
              ]
            : [
                ...state.segments,
                LiveSegment(
                  id: id,
                  at: _now(),
                  status: status,
                  text: visibleText,
                  stable: stable,
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

  /// Ends the session; sentences still on their way are dropped.
  Future<void> stop() async {
    if (_ended) return;
    _ended = true;
    _clock?.cancel();
    _holdTimer?.cancel();
    _held = null;
    await _events?.cancel();
    _events = null;
    await _conversation?.close();
    _conversation = null;
    _pending.clear();
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
    this.finalAt, {
    this.pieces = 1,
  });
  final int id;
  final Transcription transcription;
  final DateTime lastVoiceAt;
  final DateTime finalAt;

  /// How many recognizer sentences were joined into this one.
  final int pieces;

  String get text => transcription.finalTranscript;

  /// This sentence followed by [next], kept under this one's line. The
  /// confidence is weighted by each piece's length.
  _LivePlayback join(_LivePlayback next) {
    final a = text.length;
    final b = next.text.length;
    final confidence =
        (transcription.asrConfidence * a +
            next.transcription.asrConfidence * b) /
        (a + b == 0 ? 1 : a + b);
    return _LivePlayback(
      id,
      Transcription(
        traceId: next.transcription.traceId,
        finalTranscript: '$text ${next.text}',
        asrConfidence: confidence,
      ),
      next.lastVoiceAt,
      next.finalAt,
      pieces: pieces + next.pieces,
    );
  }
}
