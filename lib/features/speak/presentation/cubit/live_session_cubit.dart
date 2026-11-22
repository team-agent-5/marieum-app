import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/audio/live_audio_dump.dart';
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
import 'package:uuid/uuid.dart';

/// `finishing`: the patient stopped mid-sentence and its end is awaited.
enum LiveStatus { starting, listening, finishing, failed, closed }

enum LiveSegmentStatus { interpreting, done, unclear, failed }

/// Where a finished sentence was said aloud, with the other phone's mode.
enum LiveDelivery {
  /// Not sent anywhere yet, or not in that mode.
  none,

  /// Sent; the server has not said whether the other phone got it.
  sending,

  /// The other phone got it and is saying it.
  delivered,

  /// The other phone finished saying it.
  played,

  /// The other phone did not get it, so this phone read it.
  local,
}

class LiveSegment extends Equatable {
  const LiveSegment({
    required this.id,
    required this.at,
    this.status = LiveSegmentStatus.interpreting,
    this.text = '',
    this.delivery = LiveDelivery.none,
  });

  final int id;

  /// When the sentence first showed up.
  final DateTime at;
  final LiveSegmentStatus status;

  /// The sentence understood so far while interpreting, then the final
  /// sentence or the failure reason.
  final String text;
  final LiveDelivery delivery;

  LiveSegment copyWith({
    LiveSegmentStatus? status,
    String? text,
    LiveDelivery? delivery,
  }) => LiveSegment(
    id: id,
    at: at,
    status: status ?? this.status,
    text: text ?? this.text,
    delivery: delivery ?? this.delivery,
  );

  @override
  List<Object?> get props => [id, at, status, text, delivery];
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
    this.relay = false,
    this.listener,
  });

  final LiveStatus status;

  /// Whether sentences go to the other phone instead of this one's speaker.
  final bool relay;

  /// Whether the other phone is listening, once the server has said; only
  /// with [relay].
  final ListenerPresence? listener;

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
    ListenerPresence? listener,
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
    relay: relay,
    listener: listener ?? this.listener,
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
    relay,
    listener,
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
    SpeechSegmenter? segmenter,
    LiveSound? sound,
    this._dump,
    bool relay = false,
    String Function()? newUtteranceId,
    this.saidWait = const Duration(milliseconds: 1500),
    DateTime Function()? now,
  }) : _levels = segmenter ?? SpeechSegmenter(),
       _newUtteranceId = newUtteranceId ?? const Uuid().v4,
       _sound = sound ?? LiveSound(),
       _now = now ?? DateTime.now,
       super(LiveSessionState(relay: relay));

  static const historyLength = 32;

  /// How long after the app finishes a sentence it may still come back
  /// through the microphone.
  static const echoTail = Duration(seconds: 1);

  /// How long the other phone's voice is kept out of the recognizer when its
  /// `played` never comes.
  static const relayEchoLimit = Duration(seconds: 15);

  /// How long a sentence read here waits for an earlier one the other phone
  /// is saying.
  static const relayOrderLimit = Duration(seconds: 5);

  /// Input is not sent this long after the microphone opens while its
  /// level and gain settle; speech in it came out weak or clipped.
  static const warmUp = Duration(milliseconds: 300);

  /// How long after a sentence a piece of it heard again is taken for the
  /// recognizer starting over on its end.
  static const leftoverWindow = Duration(seconds: 5);

  /// Zeroed PCM goes out instead of the microphone while the app speaks,
  /// and after it until the input is back to the room's level, no sooner
  /// than [muteTail] and no later than [maxMuteTail]: Android cannot cancel
  /// the app's own playback from the input, and loud sound came in right
  /// after it ended while the recording was being restored. The microphone
  /// itself stays open, as restarting it at every sentence cost most of a
  /// second and recreated Android's audio effects each time.
  static const muteTail = Duration(milliseconds: 300);
  static const maxMuteTail = Duration(milliseconds: 1500);

  /// How long the server reading more of a sentence counts as hearing the
  /// patient.
  static const readHearing = Duration(milliseconds: 800);

  /// How often the input loudness is logged.
  static const levelLogEvery = Duration(seconds: 1);

  /// How long the server's `session_end` is awaited after the patient
  /// stops; it came within half a second of `end`.
  static const finishWait = Duration(milliseconds: 2500);

  final MicStream _mic;
  final LiveSound _sound;

  /// Keeps the session's audio for listening back, when turned on.
  final LiveAudioDump? _dump;
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

  /// Whether silence goes out instead of the microphone, and once the app
  /// has stopped speaking, from when and until when the input may come
  /// back.
  bool _muted = false;
  DateTime? _quietFrom;
  DateTime? _unmuteBy;

  /// The clean-up under way, shared by every call to [stop].
  Future<void>? _stopping;

  /// Finishing waits for sentences on their way to the other phone.
  bool _finishingRelays = false;

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

  final String Function() _newUtteranceId;

  /// How long the server's `said` is awaited before this phone reads the
  /// sentence itself.
  final Duration saidWait;

  /// Sentences sent to the other phone, by utterance id, until it has
  /// played them.
  final _relays = <String, _Relay>{};

  /// Sentences on their way to the other phone, awaited when finishing.
  final _relaying = <Future<void>>{};

  /// The utterance id each segment was last sent as.
  final _latestAttempt = <int, String>{};

  /// Completes once the last sentence sent is queued here or played on the
  /// other phone; the next one read here waits for it.
  Future<void> _relayOrder = Future.value();

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
      final silence = Uint8List(chunk.length);
      _conversation?.add(silence);
      _dump?.add(chunk, silence);
      _unmuteOnceQuiet(level);
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
    _dump?.add(chunk, sent);
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
      case LiveUnclear():
        // The server also reports a stretch it could not make out in the
        // middle of a sentence it goes on reading; that sentence carries on.
        if (_lastInterim != null) return;
        final id = _currentId;
        _currentId = null;
        _lastInterim = null;
        // Silence the server closed off is not worth a line.
        if (id != null) _show(id, LiveSegmentStatus.unclear, '');
      case LiveSessionEnded():
        _lastSentenceIn();
      case LiveListener(:final presence):
        if (state.relay) {
          AppLog.speak('live listener ${presence.name}');
          emit(state.copyWith(listener: presence));
        }
      case LiveSaid(:final utteranceId, :final delivered):
        final said = _relays[utteranceId]?.said;
        if (said != null && !said.isCompleted) said.complete(delivered);
      case LivePlayed(:final utteranceId):
        final relay = _relays[utteranceId];
        if (relay == null) return;
        if (!relay.played.isCompleted) relay.played.complete();
        if (!relay.said.isCompleted) {
          // Played without a `said`: it was delivered.
          relay.said.complete(true);
          return;
        }
        _relays.remove(utteranceId);
        _deliver(relay.segmentId, LiveDelivery.played, attempt: utteranceId);
        _echoEnds(relay);
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
    _readAt = null;
    // Latency is measured from the server's last reading of the sentence,
    // which every sentence with an interim has; the microphone misses quiet
    // voices. Without a reading it falls back to the microphone.
    final basis = readAt != null
        ? 'reading'
        : voiceAt != null
        ? 'mic'
        : 'final';
    final lastVoiceAt = readAt ?? voiceAt ?? finalAt;
    final confidence = transcription.asrConfidence.toStringAsFixed(4);
    String since(DateTime? at) =>
        at == null ? '-' : '${finalAt.difference(at).inMilliseconds}';
    AppLog.speak(
      'live segment $id conf=$confidence '
      'final=${finalAt.toIso8601String()} '
      'from_mic_voice_ms=${since(voiceAt)} '
      'from_last_reading_ms=${since(readAt)} latency_basis=$basis',
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
    final playback = _LivePlayback(id, transcription, lastVoiceAt, finalAt);
    if (state.relay) {
      _track(_relayOrSpeak(playback));
      return;
    }
    _pending.add(playback);
    unawaited(_drain());
  }

  void _track(Future<void> relaying) {
    _relaying.add(relaying);
    unawaited(relaying.whenComplete(() => _relaying.remove(relaying)));
  }

  /// Sends a sentence to the other phone and reads it here when the server
  /// says it did not get there, or does not answer in time; a `played` for
  /// it counts as delivered too, as the `said` may have been lost with a
  /// connection. A sentence the other phone says is kept out of the
  /// recognizer like this phone's own voice, as both are in the same room.
  ///
  /// One read here waits until every earlier sentence is either queued here
  /// or played on the other phone (for up to [relayOrderLimit]), so the
  /// sentences come out in the order they were said and do not overlap.
  /// [log] is false for a replay.
  Future<void> _relayOrSpeak(_LivePlayback phrase, {bool log = true}) async {
    final previous = _relayOrder;
    final settled = Completer<void>();
    _relayOrder = settled.future;
    var deferred = false;
    try {
      final text = phrase.transcription.finalTranscript;
      final listener = state.listener;
      _Relay? relay;
      var delivered = false;
      // Every try is the segment's latest, read here or sent.
      final attempt = _newUtteranceId();
      _latestAttempt[phrase.id] = attempt;
      if (listener == null || listener == ListenerPresence.joined) {
        final id = attempt;
        relay = _relays[id] = _Relay(id, phrase.id, text);
        _deliver(phrase.id, LiveDelivery.sending, attempt: id);
        final sent =
            _conversation?.say(
              utteranceId: id,
              text: text,
              traceId: phrase.transcription.traceId,
            ) ??
            false;
        if (sent) {
          delivered = await relay.said.future.timeout(
            saidWait,
            onTimeout: () => false,
          );
        }
      }
      if (_ended || isClosed) return;
      final at = _now();
      if (relay != null && delivered) {
        final id = relay.utteranceId;
        if (relay.played.isCompleted) {
          // Already said there; its voice may still be coming in.
          _relays.remove(id);
          _spoken.add((text: relay.echo.text, until: _now().add(echoTail)));
          _deliver(phrase.id, LiveDelivery.played, attempt: id);
        } else {
          _spoken.add(relay.echo);
          relay.echoLimit = Timer(relayEchoLimit, () {
            if (_relays.remove(id) != null) _echoEnds(relay!);
          });
          _deliver(phrase.id, LiveDelivery.delivered, attempt: id);
        }
        final latency = at.difference(phrase.lastVoiceAt);
        AppLog.speak(
          'live segment ${phrase.id} relayed as $id '
          'final_to_said_ms=${at.difference(phrase.finalAt).inMilliseconds} '
          'latency_ms=${latency.inMilliseconds}',
        );
        if (log) {
          unawaited(
            _logPlayback(phrase, latency.isNegative ? Duration.zero : latency),
          );
        }
        deferred = true;
        // Later sentences read here wait for the earlier ones too, not
        // only for this one.
        unawaited(
          Future.wait([
            previous,
            relay.played.future.timeout(relayOrderLimit, onTimeout: () {}),
          ]).whenComplete(settled.complete),
        );
        return;
      }
      if (relay != null) {
        // A late answer is ignored; this phone reads it instead.
        _relays.remove(relay.utteranceId)?.echoLimit?.cancel();
        AppLog.speak(
          'live segment ${phrase.id} not delivered, read on this phone',
        );
      }
      _deliver(phrase.id, LiveDelivery.local, attempt: attempt);
      await previous;
      if (_ended || isClosed) return;
      // A replay goes through the same queue, so it is not lost while
      // another sentence plays, and is not logged again.
      _pending.add(log ? phrase : phrase.replay());
      settled.complete();
      await _drain();
    } finally {
      if (!deferred && !settled.isCompleted) settled.complete();
    }
  }

  /// The other phone's voice stops counting as an echo shortly after it is
  /// done.
  void _echoEnds(_Relay relay) {
    relay.echoLimit?.cancel();
    if (_spoken.remove(relay.echo)) {
      _spoken.add((text: relay.echo.text, until: _now().add(echoTail)));
    }
  }

  /// Shows where segment [id] was said; [attempt], the utterance id it was
  /// sent as, keeps an earlier send's news from overwriting a replay's.
  void _deliver(int id, LiveDelivery delivery, {String? attempt}) {
    if (_ended || isClosed) return;
    if (attempt != null && _latestAttempt[id] != attempt) return;
    if (!state.segments.any((s) => s.id == id)) return;
    emit(
      state.copyWith(
        segments: [
          for (final segment in state.segments)
            if (segment.id == id)
              segment.copyWith(delivery: delivery)
            else
              segment,
        ],
      ),
    );
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
    for (final phrase in batch.where((p) => p.log)) {
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
      final now = _now();
      _quietFrom = now.add(muteTail);
      _unmuteBy = now.add(maxMuteTail);
    }
  }

  /// Sends silence instead of the microphone from before the app speaks,
  /// so neither its voice nor words said over it reach the recognizer.
  void _mute() {
    _quietFrom = _unmuteBy = null;
    if (_muted || _ended || isClosed) return;
    _muted = true;
    emit(state.copyWith(micPaused: true, hearing: false));
  }

  /// Lets the microphone through again once the app's voice has died down
  /// to the room's level, or at the latest by [maxMuteTail].
  void _unmuteOnceQuiet(double level) {
    final quietFrom = _quietFrom;
    final unmuteBy = _unmuteBy;
    if (quietFrom == null || unmuteBy == null || _lastSentence != null) return;
    final now = _now();
    if (now.isBefore(quietFrom)) return;
    final quiet = level < _levels.threshold;
    if (!quiet && now.isBefore(unmuteBy)) return;
    _muted = false;
    _quietFrom = _unmuteBy = null;
    final at = _dump == null ? '' : ' at ${_dump.seconds.toStringAsFixed(1)}s';
    AppLog.speak(
      'live microphone back${quiet ? '' : ' while still loud'}$at',
    );
    emit(state.copyWith(micPaused: false));
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
                  if (segment.id == id)
                    segment.copyWith(status: status, text: visibleText)
                  else
                    segment,
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
    if (state.relay) {
      final at = _now();
      await _relayOrSpeak(
        _LivePlayback(
          id,
          Transcription(
            traceId: _traceId,
            finalTranscript: segment.text,
            asrConfidence: 1,
          ),
          at,
          at,
        ),
        log: false,
      );
      return;
    }
    await _speak(id, segment.text);
  }

  /// Ends the session once the sentence the patient was saying is in: the
  /// server is told no more audio is coming and its finals are taken until
  /// it sends `session_end`, for up to [finishWait]. What was read of a
  /// sentence that got no final is taken as it is. Everything is spoken,
  /// then closed. Without a sentence under way, or called again while
  /// waiting, it ends at once; with the other phone, sentences already on
  /// their way there are still seen through first.
  Future<void> finish() async {
    if (_ended) return _stopping;
    final conversation = _conversation;
    if (_lastSentence != null || _finishingRelays) return stop();
    if (_lastInterim == null || conversation == null) {
      if (_relaying.isEmpty) return stop();
      _finishingRelays = true;
      AppLog.speak('live finishing, sentences on their way awaited');
      emit(state.copyWith(status: LiveStatus.finishing));
      await Future.wait([..._relaying]);
      await _draining;
      return stop();
    }
    final last = _lastSentence = Completer<void>();
    AppLog.speak('live finishing, last sentence awaited');
    emit(state.copyWith(status: LiveStatus.finishing));
    _muted = true;
    _quietFrom = _unmuteBy = null;
    conversation.end();
    await last.future.timeout(
      finishWait,
      onTimeout: () => AppLog.speak('live session_end did not come'),
    );
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
    await Future.wait([..._relaying]);
    await _draining;
    await stop();
  }

  void _lastSentenceIn() {
    final last = _lastSentence;
    if (last != null && !last.isCompleted) last.complete();
  }

  /// Ends the session at once; sentences still on their way are dropped.
  /// Every caller waits for the same clean-up.
  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    _ended = true;
    _lastSentenceIn();
    for (final relay in _relays.values) {
      relay.echoLimit?.cancel();
      if (!relay.said.isCompleted) relay.said.complete(false);
      if (!relay.played.isCompleted) relay.played.complete();
    }
    _relays.clear();
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
    await _dump?.save();
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
    this.log = true,
  });
  final int id;
  final Transcription transcription;
  final DateTime lastVoiceAt;
  final DateTime finalAt;

  /// False for a replay, which was logged the first time.
  final bool log;

  _LivePlayback replay() =>
      _LivePlayback(id, transcription, lastVoiceAt, finalAt, log: false);
}

/// A sentence sent to the other phone.
class _Relay {
  _Relay(this.utteranceId, this.segmentId, String text)
    : echo = (text: text, until: null);
  final String utteranceId;
  final int segmentId;
  final said = Completer<bool>();
  final played = Completer<void>();

  /// Kept in the echo list while the other phone may be saying it.
  final ({String text, DateTime? until}) echo;
  Timer? echoLimit;
}
