import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/audio/live_sound.dart';
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

/// `finishing`: the patient stopped mid-sentence and its end is awaited.
enum LiveStatus { starting, listening, finishing, failed, closed }

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
    this.micPaused = false,
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

  /// The segment actually playing.
  final int? playingId;

  /// Whether silence goes out instead of the microphone around the app's
  /// voice, so words said now are not heard.
  final bool micPaused;
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
    bool? micPaused,
    Duration? elapsed,
    List<LiveSegment>? segments,
    Failure? failure,
  }) => LiveSessionState(
    status: status ?? this.status,
    levels: levels ?? this.levels,
    hearing: hearing ?? this.hearing,
    threshold: threshold ?? this.threshold,
    playingId: playingId == null ? this.playingId : playingId(),
    micPaused: micPaused ?? this.micPaused,
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
    micPaused,
    elapsed,
    segments,
    failure,
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
    SpeechSegmenter? segmenter,
    LiveSound? sound,
    DateTime Function()? now,
  }) : _levels = segmenter ?? SpeechSegmenter(),
       _sound = sound ?? LiveSound(),
       _now = now ?? DateTime.now,
       super(const LiveSessionState());

  static const historyLength = 32;

  /// How long after the app finishes a sentence it may still come back
  /// through the microphone.
  static const echoTail = Duration(seconds: 1);

  /// Input is not sent this long after the microphone opens while its
  /// level and gain settle; speech in it came out weak or clipped.
  static const warmUp = Duration(milliseconds: 300);

  /// How long after a sentence a piece of it heard again is taken for the
  /// recognizer starting over on its end.
  static const leftoverWindow = Duration(seconds: 5);

  /// How long after the app's voice ends silence still goes out instead of
  /// the microphone, while the sound and the audio buffers die down.
  static const muteTail = Duration(milliseconds: 500);

  /// How long after the last sentence's final further finals are taken
  /// while finishing; the server does not say which final is the last.
  static const finishGrace = Duration(milliseconds: 700);

  /// How long the server reading more of a sentence counts as hearing the
  /// patient.
  static const readHearing = Duration(milliseconds: 800);

  /// How often the input loudness is logged.
  static const levelLogEvery = Duration(seconds: 1);

  /// How long the sentence under way is awaited after the patient stops.
  static const finishWait = Duration(milliseconds: 2500);

  /// Sends zeroed PCM instead of the microphone while the app speaks and
  /// for [muteTail] after. Android cannot cancel the app's own media
  /// playback from the input, and what iOS echo cancellation leaves still
  /// reached the recognizer as stray syllables. The microphone itself stays
  /// open: restarting it at every sentence cost most of a second and
  /// recreated Android's audio effects each time.
  final bool muteWhileSpeaking;

  final MicStream _mic;
  final LiveSound _sound;
  final LiveStream _stream;
  final UtteranceRepository _repository;
  final PlaybackTtsPort _tts;

  /// Only tracks the room's loudness for the input display; sentences are
  /// split by the server.
  final SpeechSegmenter _levels;
  final DateTime Function() _now;

  StreamSubscription<Uint8List>? _input;
  LiveConversation? _conversation;
  StreamSubscription<LiveEvent>? _events;
  Timer? _clock;
  final _pending = <_LivePlayback>[];
  Future<void>? _draining;
  int _nextId = 0;
  bool _ended = false;
  bool _speechBusy = false;
  DateTime? _warmUntil;

  /// Whether silence goes out instead of the microphone.
  bool _muted = false;
  Timer? _unmute;

  /// While finishing, completes once the last sentence is in.
  Completer<void>? _lastSentence;

  /// The session's trace id, from the server's transcripts.
  String _traceId = '';

  /// When the server last read more of a sentence; quiet voices it hears
  /// can stay under the input level.
  DateTime? _readAt;

  /// Input power gathered since [_levelSince] for the log.
  DateTime? _levelSince;
  int _levelCount = 0;
  double _heardPower = 0;
  double _sentPower = 0;
  double _heardPeak = 0;
  double _sentPeak = 0;

  /// The sentence the server is reading now, shown as it changes.
  int? _currentId;

  /// The latest reading of the sentence in progress, kept in case the
  /// final comes back looping.
  String? _lastInterim;

  /// When the microphone last heard a voice above the room level.
  DateTime? _voiceAt;

  /// The last sentence the server finished, and when.
  ({String text, DateTime at})? _lastFinal;

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
      // Connecting takes about a second; it starts while the microphone
      // settles so less audio waits for it.
      final conversation = _conversation = _stream.connect();
      _events = conversation.events.listen(_onEvent);
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
    }
    if (_muted) {
      // Zeroed PCM, as the recognizer's team asks, at the microphone's own
      // pace; the app's voice is kept out of the room level and the gain.
      _conversation?.add(Uint8List(chunk.length));
      emit(
        state.copyWith(
          levels: [...levels.take(levels.length - 1), 0],
          hearing: false,
        ),
      );
      return;
    }
    _levels.add(chunk, level: level);
    if (_levels.hearing) _voiceAt = _now();
    final sent = _sound.process(chunk);
    _conversation?.add(sent);
    _logLevel(chunk, sent);
    final readAt = _readAt;
    emit(
      state.copyWith(
        levels: levels,
        hearing:
            _levels.hearing ||
            (readAt != null && _now().difference(readAt) < readHearing),
        threshold: _levels.threshold,
      ),
    );
  }

  void _onEvent(LiveEvent event) {
    if (_ended || isClosed) return;
    switch (event) {
      case LiveInterim(:final text, :final traceId):
        if (_isEcho(text)) return;
        if (traceId.isNotEmpty) _traceId = traceId;
        final id = _currentId ??= _nextId++;
        // More of the sentence was read, so the patient was just speaking.
        if (text != _lastInterim) _readAt = _now();
        _lastInterim = text;
        _clearFailure();
        _show(id, LiveSegmentStatus.interpreting, text);
      case LiveFinal(:final transcription):
        if (transcription.traceId.isNotEmpty) _traceId = transcription.traceId;
        final id = _currentId ?? _nextId++;
        _currentId = null;
        final interim = _lastInterim;
        _lastInterim = null;
        _clearFailure();
        _settle(id, _unlooped(id, transcription, interim));
        _lastSentenceIn();
      case LiveUnclear():
        // The server also reports a stretch it could not make out in the
        // middle of a sentence it goes on reading; that sentence carries on.
        if (_lastInterim != null) return;
        final id = _currentId;
        _currentId = null;
        _lastInterim = null;
        // Silence the server closed off is not worth a line.
        if (id != null) _show(id, LiveSegmentStatus.unclear, '');
        _lastSentenceIn();
      case LiveFailed(:final failure, :final recovering):
        // Finishing goes on with what was read of the sentence so far.
        if (_lastSentence != null) {
          _lastSentenceIn();
          return;
        }
        if (!recovering) {
          emit(state.copyWith(status: LiveStatus.failed, failure: failure));
          return;
        }
        if (_showingFailure) return;
        _showingFailure = true;
        final id = _currentId ?? _nextId++;
        _currentId = null;
        _lastInterim = null;
        _show(id, LiveSegmentStatus.failed, failure.message);
    }
  }

  void _clearFailure() => _showingFailure = false;

  /// The recognizer decodes the final again and sometimes loops on a
  /// phrase its interim readings never repeated; the last of those is
  /// then the better sentence.
  Transcription _unlooped(int id, Transcription final_, String? interim) {
    if (interim == null ||
        !LivePhrasePolicy.repeats(final_.finalTranscript) ||
        LivePhrasePolicy.repeats(interim) ||
        LivePhrasePolicy.isFragment(interim)) {
      return final_;
    }
    AppLog.speak('live segment $id final looped, last interim used');
    return Transcription(
      traceId: final_.traceId,
      finalTranscript: interim,
      asrConfidence: final_.asrConfidence,
      heardText: interim,
    );
  }

  /// Logs the input loudness once a second in dBFS, as heard and as sent
  /// after processing, to tell quiet speech from speech that never got
  /// through. Power is averaged before converting, so quiet stretches are
  /// not cut off at the bottom of the input display's scale.
  void _logLevel(Uint8List heard, Uint8List sent) {
    final now = _now();
    final since = _levelSince ??= now;
    final heardPower = pcmPower(heard);
    final sentPower = pcmPower(sent);
    _levelCount++;
    _heardPower += heardPower;
    _sentPower += sentPower;
    if (heardPower > _heardPeak) _heardPeak = heardPower;
    if (sentPower > _sentPeak) _sentPeak = sentPower;
    if (now.difference(since) < levelLogEvery) return;
    String dbfs(double power) => power <= 0
        ? '-inf'
        : (10 * math.log(power) / math.ln10).toStringAsFixed(1);
    AppLog.speak(
      'live input dBFS mic avg=${dbfs(_heardPower / _levelCount)} '
      'peak=${dbfs(_heardPeak)} '
      'sent avg=${dbfs(_sentPower / _levelCount)} peak=${dbfs(_sentPeak)} '
      'voice=${_levels.hearing}',
    );
    _levelSince = now;
    _levelCount = 0;
    _heardPower = _sentPower = _heardPeak = _sentPeak = 0;
  }

  void _settle(int id, Transcription transcription) {
    final finalAt = _now();
    final voiceAt = _voiceAt;
    final readAt = _readAt;
    // The microphone can miss a quiet voice the server still reads, so the
    // later of the two is taken as where the patient stopped.
    final lastVoiceAt =
        voiceAt != null && (readAt == null || voiceAt.isAfter(readAt))
        ? voiceAt
        : readAt ?? finalAt;
    final confidence = transcription.asrConfidence.toStringAsFixed(4);
    String since(DateTime? at) =>
        at == null ? '-' : '${finalAt.difference(at).inMilliseconds}';
    AppLog.speak(
      'live segment $id conf=$confidence '
      'final=${finalAt.toIso8601String()} '
      'from_mic_voice_ms=${since(voiceAt)} '
      'from_last_reading_ms=${since(readAt)}',
    );
    if (_isEcho(transcription.finalTranscript)) {
      AppLog.speak("live segment $id conf=$confidence was the app's own voice");
      _remove(id);
      return;
    }
    final last = _lastFinal;
    if (last != null &&
        finalAt.difference(last.at) < leftoverWindow &&
        LivePhrasePolicy.isLeftover(transcription.finalTranscript, last.text)) {
      AppLog.speak(
        'live segment $id conf=$confidence '
        'repeated the end of the last sentence',
      );
      _remove(id);
      return;
    }
    _lastFinal = (text: transcription.finalTranscript, at: finalAt);
    // Spoken whatever its confidence: in live mode the patient hears it at
    // once and can say it again.
    if (transcription.finalTranscript.trim().isEmpty ||
        transcription.finalTranscript.contains('�')) {
      _show(
        id,
        LiveSegmentStatus.unclear,
        LivePhrasePolicy.displayText(transcription.heard),
      );
      return;
    }
    _show(id, LiveSegmentStatus.done, transcription.finalTranscript);
    _pending.add(_LivePlayback(id, transcription, lastVoiceAt, finalAt));
    unawaited(_drain());
  }

  /// Speaks waiting sentences. Those that arrived while another was playing
  /// are read together in one go, so a patient who keeps talking is not
  /// held up sentence by sentence.
  Future<void> _drain() =>
      _draining ??= _speakPending().whenComplete(() => _draining = null);

  Future<void> _speakPending() async {
    while (_pending.isNotEmpty && !_ended && !isClosed) {
      final batch = [..._pending];
      _pending.clear();
      await _speakAndLog(batch);
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
      batch.map((p) => p.transcription.finalTranscript).join(' '),
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
    _mute();
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
          onStarted?.call(at);
        },
        onEnded: finishPlayback,
      );
    } on Object {
      return const FailureResult(TtsFailure('음성을 재생하지 못했어요.'));
    } finally {
      finishPlayback();
      _speechBusy = false;
      _unmuteSoon();
    }
  }

  /// Sends silence instead of the microphone from before the app speaks,
  /// so neither its voice nor words said over it reach the recognizer.
  void _mute() {
    _unmute?.cancel();
    _unmute = null;
    if (!muteWhileSpeaking || _muted || _ended || isClosed) return;
    _muted = true;
    emit(state.copyWith(micPaused: true, hearing: false));
  }

  void _unmuteSoon() {
    if (!_muted || _ended || isClosed) return;
    _unmute?.cancel();
    _unmute = Timer(muteTail, () {
      _unmute = null;
      if (_speechBusy || _lastSentence != null || _ended || isClosed) return;
      _muted = false;
      AppLog.speak('live microphone back');
      emit(state.copyWith(micPaused: false));
    });
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

  /// Ends the session once the sentence the patient was saying is in: the
  /// server is told no more audio is coming, its last sentence awaited for
  /// up to [finishWait] (or what was read of it so far taken) and spoken,
  /// then everything closes. Without a sentence under way, or called again
  /// while waiting, it ends at once.
  Future<void> finish() async {
    if (_ended) return;
    final conversation = _conversation;
    if (_lastSentence != null || _lastInterim == null || conversation == null) {
      return stop();
    }
    final last = _lastSentence = Completer<void>();
    AppLog.speak('live finishing, last sentence awaited');
    emit(state.copyWith(status: LiveStatus.finishing));
    _unmute?.cancel();
    _muted = true;
    conversation.end();
    var finalCame = false;
    await last.future
        .then((_) => finalCame = _lastInterim == null)
        .timeout(finishWait, onTimeout: () => false);
    // The server does not mark its last final, so one more after the first
    // is waited for briefly.
    if (finalCame && !_ended) await Future<void>.delayed(finishGrace);
    final id = _currentId;
    final interim = _lastInterim;
    if (!_ended && id != null && interim != null) {
      AppLog.speak('live segment $id ended without a final, reading used');
      _currentId = null;
      _lastInterim = null;
      _settle(
        id,
        Transcription(
          traceId: _traceId,
          finalTranscript: interim,
          asrConfidence: 0,
        ),
      );
    }
    await _draining;
    await stop();
  }

  void _lastSentenceIn() {
    final last = _lastSentence;
    if (last != null && !last.isCompleted) last.complete();
  }

  /// Ends the session at once; sentences still on their way are dropped.
  Future<void> stop() async {
    if (_ended) return;
    _ended = true;
    _lastSentenceIn();
    _unmute?.cancel();
    _clock?.cancel();
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
    this.finalAt,
  );
  final int id;
  final Transcription transcription;
  final DateTime lastVoiceAt;
  final DateTime finalAt;
}
