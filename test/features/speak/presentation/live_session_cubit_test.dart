import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/live_audio_dump.dart';
import 'package:marieum_app/core/audio/mic_stream.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:marieum_app/features/speak/domain/repositories/live_stream.dart';
import 'package:marieum_app/features/speak/domain/repositories/utterance_repository.dart';
import 'package:marieum_app/features/speak/presentation/cubit/live_session_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockMic extends Mock implements MicStream {}

class _MockRepository extends Mock implements UtteranceRepository {}

class _MockTts extends Mock implements PlaybackTtsPort {}

class _FakeConversation implements LiveConversation {
  final server = StreamController<LiveEvent>();
  final sent = <Uint8List>[];
  bool ended = false;
  @override
  Stream<LiveEvent> get events => server.stream;
  @override
  void add(Uint8List audio) => sent.add(audio);
  @override
  void end() => ended = true;
  @override
  Future<void> close() => server.close();
}

class _FakeStream implements LiveStream {
  _FakeStream(this._clock);
  final DateTime Function() _clock;
  final conversation = _FakeConversation();
  DateTime? connectedAt;
  @override
  LiveConversation connect() {
    connectedAt = _clock();
    return conversation;
  }
}

/// 100 ms loud enough to count as a voice.
final _voice = Uint8List.fromList(List.generate(3200, (i) => i % 256));

Transcription _heard(String text, double confidence) => Transcription(
  traceId: 'trace',
  finalTranscript: text,
  asrConfidence: confidence,
);

void main() {
  setUpAll(() {
    registerFallbackValue(_heard('', 0));
    registerFallbackValue(Duration.zero);
  });

  group(LiveSessionCubit, () {
    late _MockMic mic;
    late _MockRepository repository;
    late _MockTts tts;
    late _FakeStream stream;
    late List<StreamController<Uint8List>> inputs;
    late DateTime now;
    late LiveSessionCubit cubit;
    late Directory folder;
    late LiveAudioDump dump;

    /// When set, the app's voice plays until it completes.
    Completer<void>? speech;

    void verifySpoken(String text) => verify(
      () => tts.speakWithPlayback(
        text,
        onStarted: any(named: 'onStarted'),
        onEnded: any(named: 'onEnded'),
      ),
    ).called(1);

    void verifyNothingSpoken() => verifyNever(
      () => tts.speakWithPlayback(
        any(),
        onStarted: any(named: 'onStarted'),
        onEnded: any(named: 'onEnded'),
      ),
    );

    setUp(() async {
      folder = Directory.systemTemp.createTempSync('live_audio_test');
      dump = LiveAudioDump(directory: () async => folder);
      mic = _MockMic();
      repository = _MockRepository();
      tts = _MockTts();
      now = DateTime(2026, 11, 20, 12);
      stream = _FakeStream(() => now);
      inputs = [];
      speech = null;
      when(mic.start).thenAnswer((_) async {
        final input = StreamController<Uint8List>();
        inputs.add(input);
        return input.stream;
      });
      when(mic.stop).thenAnswer((_) async {});
      when(mic.dispose).thenAnswer((_) async {});
      when(tts.stop).thenAnswer((_) async => const Success(null));
      when(
        () => tts.speakWithPlayback(
          any(),
          onStarted: any(named: 'onStarted'),
          onEnded: any(named: 'onEnded'),
        ),
      ).thenAnswer((call) async {
        (call.namedArguments[#onStarted] as void Function())();
        await speech?.future;
        (call.namedArguments[#onEnded] as void Function())();
        return const Success(null);
      });
      when(
        () => repository.bypass(any(), latency: any(named: 'latency')),
      ).thenAnswer((_) async => const Success('log'));
      cubit = LiveSessionCubit(
        mic: mic,
        stream: stream,
        repository: repository,
        tts: tts,
        dump: dump,
        now: () => now,
      );
      await cubit.start();
      now = now.add(LiveSessionCubit.warmUp);
      inputs.last.add(Uint8List(3200));
      await pumpEventQueue();
    });

    tearDown(() async {
      await cubit.close();
      folder.deleteSync(recursive: true);
    });

    test('speaks a sentence however low its confidence', () async {
      stream.conversation.server.add(LiveFinal(_heard('물 주세요', 0.2)));
      await pumpEventQueue();

      expect(cubit.state.segments.single.status, LiveSegmentStatus.done);
      verifySpoken('물 주세요');
    });

    test('connects while the microphone settles', () {
      expect(stream.connectedAt, DateTime(2026, 11, 20, 12));
    });

    test('sends silence instead of the microphone while speaking', () async {
      final playing = speech = Completer<void>();
      stream.conversation.server.add(LiveFinal(_heard('물 주세요', 0.6)));
      await pumpEventQueue();
      expect(cubit.state.micPaused, isTrue);

      // Zeroed PCM at the microphone's own pace, which stays open.
      inputs.last.add(_voice);
      await pumpEventQueue();
      expect(stream.conversation.sent.last, Uint8List(3200));

      playing.complete();
      await pumpEventQueue();
      now = now.add(LiveSessionCubit.muteTail);
      inputs.last.add(Uint8List(3200));
      await pumpEventQueue();
      expect(cubit.state.micPaused, isFalse);

      inputs.last.add(_voice);
      await pumpEventQueue();
      expect(stream.conversation.sent.last, isNot(Uint8List(3200)));
      verifyNever(mic.stop);
      verify(mic.start).called(1);
    });

    test('holds the microphone back while the room is still loud', () async {
      stream.conversation.server.add(LiveFinal(_heard('물 주세요', 0.6)));
      await pumpEventQueue();

      // Quiet input before the tail is over still stays out.
      inputs.last.add(Uint8List(3200));
      await pumpEventQueue();
      expect(cubit.state.micPaused, isTrue);

      now = now.add(LiveSessionCubit.muteTail);
      inputs.last.add(_voice);
      await pumpEventQueue();
      expect(cubit.state.micPaused, isTrue);
      expect(stream.conversation.sent.last, Uint8List(3200));

      now = now.add(LiveSessionCubit.maxMuteTail);
      inputs.last.add(_voice);
      await pumpEventQueue();
      expect(cubit.state.micPaused, isFalse);
    });

    test('keeps what was heard and what was sent side by side', () async {
      stream.conversation.server.add(LiveFinal(_heard('물 주세요', 0.6)));
      await pumpEventQueue();
      inputs.last.add(_voice);
      await pumpEventQueue();
      await cubit.stop();

      final files = folder.listSync(recursive: true).whereType<File>();
      final mic = files.singleWhere((f) => f.path.endsWith('_mic.wav'));
      final sent = files.singleWhere((f) => f.path.endsWith('_sent.wav'));
      expect(mic.lengthSync(), sent.lengthSync());
      // The voice while the app spoke went out as silence.
      expect(sent.readAsBytesSync().sublist(sent.lengthSync() - 3200), [
        for (var i = 0; i < 3200; i++) 0,
      ]);
      expect(mic.readAsBytesSync().sublist(mic.lengthSync() - 3200), _voice);
    });

    test('finishes the sentence under way before closing', () async {
      stream.conversation.server.add(const LiveInterim('물 좀'));
      await pumpEventQueue();

      final finishing = cubit.finish();
      await pumpEventQueue();
      expect(cubit.state.status, LiveStatus.finishing);
      expect(stream.conversation.ended, isTrue);

      // As the server sends it: the final, not marked last, then the end.
      stream.conversation.server
        ..add(LiveFinal(_heard('물 좀 주세요', 0.5)))
        ..add(const LiveSessionEnded());
      await finishing;
      verifySpoken('물 좀 주세요');
      expect(cubit.state.status, LiveStatus.closed);
    });

    test(
      'reads out what was heard when the session ends without a final',
      () async {
        stream.conversation.server.add(const LiveInterim('물 좀 주세요'));
        await pumpEventQueue();

        final finishing = cubit.finish();
        await pumpEventQueue();
        stream.conversation.server.add(const LiveSessionEnded());
        await finishing;
        verifySpoken('물 좀 주세요');
      },
    );

    test('reads out what was heard when the connection fails', () async {
      stream.conversation.server.add(
        const LiveInterim('물 좀 주세요', traceId: 'session'),
      );
      await pumpEventQueue();

      final finishing = cubit.finish();
      await pumpEventQueue();
      stream.conversation.server.add(const LiveFailed(NetworkFailure()));
      await finishing;
      verifySpoken('물 좀 주세요');
      expect(cubit.state.status, LiveStatus.closed);
      final logged =
          verify(
                () => repository.bypass(
                  captureAny(),
                  latency: any(named: 'latency'),
                ),
              ).captured.single
              as Transcription;
      expect(logged.traceId, 'session');
    });

    test('takes every final until the session ends', () async {
      stream.conversation.server.add(const LiveInterim('물 좀'));
      await pumpEventQueue();

      final finishing = cubit.finish();
      await pumpEventQueue();
      stream.conversation.server.add(LiveFinal(_heard('물 좀', 0.5)));
      await pumpEventQueue();
      expect(cubit.state.status, LiveStatus.finishing);
      stream.conversation.server
        ..add(LiveFinal(_heard('주세요', 0.5)))
        ..add(const LiveSessionEnded());
      await finishing;
      expect(cubit.state.segments.map((s) => s.text), ['물 좀', '주세요']);
    });

    test('ends at once without a sentence under way', () async {
      await cubit.finish();

      expect(cubit.state.status, LiveStatus.closed);
      expect(stream.conversation.ended, isFalse);
    });

    test('a second stop ends the wait at once', () async {
      stream.conversation.server.add(const LiveInterim('물 좀'));
      await pumpEventQueue();

      final finishing = cubit.finish();
      await pumpEventQueue();
      await cubit.stop();
      await finishing;
      verifyNothingSpoken();
      expect(cubit.state.status, LiveStatus.closed);
    });

    test('drops the end of the last sentence heard again', () async {
      stream.conversation.server.add(
        LiveFinal(_heard('책상이 가방이 있습니다', 0.3)),
      );
      await pumpEventQueue();
      now = now.add(const Duration(seconds: 2));
      stream.conversation.server
        ..add(const LiveInterim('가방이'))
        ..add(LiveFinal(_heard('가방이', 0.46)));
      await pumpEventQueue();

      expect(cubit.state.segments.single.text, '책상이 가방이 있습니다');
      verifySpoken('책상이 가방이 있습니다');
    });

    test('speaks part of an earlier sentence said again later', () async {
      stream.conversation.server.add(
        LiveFinal(_heard('책상이 가방이 있습니다', 0.3)),
      );
      await pumpEventQueue();
      now = now.add(LiveSessionCubit.leftoverWindow);
      stream.conversation.server.add(LiveFinal(_heard('가방이', 0.46)));
      await pumpEventQueue();

      expect(cubit.state.segments.map((s) => s.text), [
        '책상이 가방이 있습니다',
        '가방이',
      ]);
    });

    test('counts the server reading more as hearing the patient', () async {
      stream.conversation.server.add(const LiveInterim('물 좀'));
      await pumpEventQueue();
      inputs.last.add(Uint8List(3200));
      await pumpEventQueue();

      expect(cubit.state.hearing, isTrue);
    });

    test('keeps a sentence going through an unclear stretch', () async {
      stream.conversation.server
        ..add(const LiveInterim('아빠와 동물원에'))
        ..add(const LiveUnclear())
        ..add(const LiveInterim('아빠와 동물원에 갑니다'))
        ..add(LiveFinal(_heard('아빠와 동물원에 갑니다', 0.3)));
      await pumpEventQueue();

      final segment = cubit.state.segments.single;
      expect(segment.status, LiveSegmentStatus.done);
      expect(segment.text, '아빠와 동물원에 갑니다');
    });

    test('adds no line for silence the server closed off', () async {
      stream.conversation.server.add(const LiveUnclear());
      await pumpEventQueue();

      expect(cubit.state.segments, isEmpty);
    });

    test('still does not speak a sentence with broken letters', () async {
      stream.conversation.server.add(LiveFinal(_heard('물 �세요', 0.95)));
      await pumpEventQueue();

      expect(cubit.state.segments.single.status, LiveSegmentStatus.unclear);
      verifyNothingSpoken();
    });
  });
}
