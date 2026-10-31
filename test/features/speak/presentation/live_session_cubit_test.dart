import 'dart:async';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/mic_stream.dart';
import 'package:marieum_app/core/audio/speech_segmenter.dart';
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

class _MockSegmenter extends Mock implements SpeechSegmenter {}

class _FakeUtterance implements LiveUtterance {
  final controller = StreamController<LiveEvent>();
  final audio = <int>[];
  bool ended = false;
  bool cancelled = false;

  @override
  Stream<LiveEvent> get events => controller.stream;

  @override
  void add(Uint8List bytes) => audio.addAll(bytes);

  @override
  void end() => ended = true;

  @override
  void cancel() {
    cancelled = true;
    unawaited(controller.close());
  }

  void finish(LiveEvent event) {
    controller.add(event);
    unawaited(controller.close());
  }
}

class _FakeStream implements LiveStream {
  final opened = <_FakeUtterance>[];

  @override
  LiveUtterance open() {
    final utterance = _FakeUtterance();
    opened.add(utterance);
    return utterance;
  }
}

const _clear = Transcription(
  traceId: 't1',
  finalTranscript: '물 좀 주세요',
  asrConfidence: 0.9,
);

void main() {
  group(LiveSessionCubit, () {
    late _MockMic mic;
    late _FakeStream stream;
    late _MockRepository repository;
    late _MockTts tts;
    late _MockSegmenter segmenter;
    late StreamController<Uint8List> input;
    late Completer<Result<void>> speaking;
    late DateTime now;
    late bool startImmediately;
    late void Function() playbackStarted;
    late void Function() playbackEnded;

    setUpAll(() {
      registerFallbackValue(_clear);
      registerFallbackValue(Duration.zero);
      registerFallbackValue(Uint8List(0));
    });
    setUp(() {
      mic = _MockMic();
      stream = _FakeStream();
      repository = _MockRepository();
      tts = _MockTts();
      segmenter = _MockSegmenter();
      input = StreamController<Uint8List>.broadcast();
      speaking = Completer();
      now = DateTime(2026, 10, 31, 12);
      startImmediately = true;
      when(mic.start).thenAnswer((_) async => input.stream);
      when(mic.stop).thenAnswer((_) async {});
      when(mic.dispose).thenAnswer((_) async {});
      when(
        () => tts.speakWithPlayback(
          any(),
          onStarted: any(named: 'onStarted'),
          onEnded: any(named: 'onEnded'),
        ),
      ).thenAnswer((call) async {
        playbackStarted = call.namedArguments[#onStarted]! as void Function();
        playbackEnded = call.namedArguments[#onEnded]! as void Function();
        if (startImmediately) playbackStarted();
        final result = await speaking.future;
        playbackEnded();
        return result;
      });
      when(tts.stop).thenAnswer((_) async {
        if (!speaking.isCompleted) {
          speaking.complete(const FailureResult(TtsFailure('stopped')));
        }
        return const Success(null);
      });
      when(
        () => repository.bypass(any(), latency: any(named: 'latency')),
      ).thenAnswer((_) async => const Success('기록'));
      when(() => segmenter.hearing).thenReturn(false);
      when(() => segmenter.threshold).thenReturn(0.35);
      when(segmenter.reset).thenReturn(null);
    });
    tearDown(() async => input.close());

    LiveSessionCubit build() => LiveSessionCubit(
      mic: mic,
      stream: stream,
      repository: repository,
      tts: tts,
      segmenter: segmenter,
      now: () => now,
    );

    /// Starts the cubit and lets the microphone warm up.
    Future<void> listen(LiveSessionCubit cubit) async {
      await cubit.start();
      now = now.add(LiveSessionCubit.warmUp);
      when(
        () => segmenter.add(any(), level: any(named: 'level')),
      ).thenReturn(null);
      input.add(Uint8List(3200));
      await pumpEventQueue();
    }

    Future<void> signal(SegmentSignal next) async {
      now = now.add(const Duration(milliseconds: 100));
      when(
        () => segmenter.add(any(), level: any(named: 'level')),
      ).thenReturn(next);
      input.add(Uint8List(3200));
      await pumpEventQueue();
    }

    Future<_FakeUtterance> phrase(String text, {bool end = true}) async {
      await signal(SegmentStarted(Uint8List(3200)));
      final session = stream.opened.last;
      if (end) await signal(SegmentEnded(Uint8List(3200), kept: true));
      now = now.add(const Duration(milliseconds: 250));
      session.finish(
        LiveFinal(
          Transcription(
            traceId: 't${stream.opened.length}',
            finalTranscript: text,
            asrConfidence: 0.9,
          ),
        ),
      );
      await pumpEventQueue();
      return session;
    }

    void verifySpeech(String text) => verify(
      () => tts.speakWithPlayback(
        text,
        onStarted: any(named: 'onStarted'),
        onEnded: any(named: 'onEnded'),
      ),
    ).called(1);
    void verifyNoSpeech() => verifyNever(
      () => tts.speakWithPlayback(
        any(),
        onStarted: any(named: 'onStarted'),
        onEnded: any(named: 'onEnded'),
      ),
    );

    test("listens past the app's own voice while it speaks", () async {
      final cubit = build();
      addTearDown(cubit.close);
      await listen(cubit);
      await phrase('물 좀 주세요');
      // Until the app's loudness is known, nothing counts as voice.
      verify(() => segmenter.playbackFloor = 1).called(1);

      when(
        () => segmenter.add(any(), level: any(named: 'level')),
      ).thenReturn(null);
      // A steady -20 dBFS tone, level 0.6.
      final echo = ByteData(3200);
      for (var i = 0; i < 1600; i++) {
        echo.setInt16(i * 2, 3277, Endian.little);
      }
      input.add(echo.buffer.asUint8List());
      await pumpEventQueue();
      now = now.add(LiveSessionCubit.echoProbe);
      input.add(Uint8List(3200));
      await pumpEventQueue();
      final floors = verify(
        () => segmenter.playbackFloor = captureAny(),
      ).captured;
      expect(floors.single as double, closeTo(0.72, 0.01));

      speaking.complete(const Success(null));
      await pumpEventQueue();
      verify(() => segmenter.playbackFloor = null).called(1);
    });

    blocTest<LiveSessionCubit, LiveSessionState>(
      'shows interim immediately and speaks a completed final before logging',
      build: build,
      act: (cubit) async {
        await listen(cubit);
        await signal(SegmentStarted(Uint8List(3200)));
        stream.opened.single.controller.add(const LiveInterim('물 좀'));
        await pumpEventQueue();
        expect(cubit.state.segments.single.text, '물 좀');
        await signal(SegmentEnded(Uint8List(3200), kept: true));
        stream.opened.single.finish(const LiveFinal(_clear));
        await pumpEventQueue();
        expect(cubit.state.playing, isTrue);
        verifySpeech('물 좀 주세요');
        verifyNever(
          () => repository.bypass(any(), latency: any(named: 'latency')),
        );
        speaking.complete(const Success(null));
        await pumpEventQueue();
        expect(cubit.state.playing, isFalse);
        verify(
          () => repository.bypass(_clear, latency: any(named: 'latency')),
        ).called(1);
      },
    );
    blocTest<LiveSessionCubit, LiveSessionState>(
      'holds an early server final and speaks the whole sentence once',
      build: build,
      act: (cubit) async {
        await listen(cubit);
        await phrase('책상', end: false);
        expect(stream.opened, hasLength(2));
        expect(stream.opened.last.audio, isEmpty);
        expect(cubit.state.segments.single.text, '책상');
        expect(
          cubit.state.segments.single.status,
          LiveSegmentStatus.interpreting,
        );
        verifyNoSpeech();

        await signal(SegmentContinued(Uint8List.fromList([1, 2, 3, 4])));
        expect(stream.opened.last.audio, [1, 2, 3, 4]);
        await signal(SegmentEnded(Uint8List(0), kept: true));
        stream.opened.last.finish(
          const LiveFinal(
            Transcription(
              traceId: 't2',
              finalTranscript: '위에 놔 주세요',
              asrConfidence: 0.9,
            ),
          ),
        );
        await pumpEventQueue();
        expect(cubit.state.segments.single.text, '책상 위에 놔 주세요');
        verifySpeech('책상 위에 놔 주세요');
      },
    );
    blocTest<LiveSessionCubit, LiveSessionState>(
      'plays every valid final immediately '
      'without waiting for a sentence ending',
      build: build,
      act: (cubit) async {
        await listen(cubit);
        await phrase('책상');
        expect(cubit.state.segments.single.text, '책상');
        verifySpeech('책상');
      },
    );
    blocTest<LiveSessionCubit, LiveSessionState>(
      'serializes finals while bypass HTTP responses remain pending',
      build: build,
      act: (cubit) async {
        final http = Completer<Result<String>>();
        when(
          () => repository.bypass(any(), latency: any(named: 'latency')),
        ).thenAnswer((_) => http.future);
        await listen(cubit);
        await phrase('첫 문장');
        await phrase('다음 문장');
        verifySpeech('첫 문장');
        verifyNever(
          () => tts.speakWithPlayback(
            '다음 문장',
            onStarted: any(named: 'onStarted'),
            onEnded: any(named: 'onEnded'),
          ),
        );
        speaking.complete(const Success(null));
        await pumpEventQueue();
        verifySpeech('다음 문장');
        expect(http.isCompleted, isFalse);
        http.complete(const Success('기록'));
      },
    );
    blocTest<LiveSessionCubit, LiveSessionState>(
      'does not filter before playback starts '
      'and records real start latency',
      build: build,
      act: (cubit) async {
        startImmediately = false;
        await listen(cubit);
        await phrase('물 좀 주세요');
        expect(cubit.state.playing, isFalse);
        await signal(SegmentStarted(Uint8List(3200)));
        stream.opened.last.controller.add(const LiveInterim('물 좀 주세요'));
        await pumpEventQueue();
        expect(cubit.state.segments.last.text, '물 좀 주세요');
        now = now.add(const Duration(milliseconds: 700));
        playbackStarted();
        expect(cubit.state.playing, isTrue);
        speaking.complete(const Success(null));
        await pumpEventQueue();
        final latency =
            verify(
                  () => repository.bypass(
                    any(),
                    latency: captureAny(named: 'latency'),
                  ),
                ).captured.single
                as Duration;
        expect(latency.inMilliseconds, 1150);
      },
    );
    blocTest<LiveSessionCubit, LiveSessionState>(
      'filters only similar sentences during playback and its one second tail',
      build: build,
      act: (cubit) async {
        await listen(cubit);
        await phrase('물 좀 주세요');
        await phrase('물 좀 주세요.');
        expect(cubit.state.segments, hasLength(1));
        speaking.complete(const Success(null));
        await pumpEventQueue();
        now = now.add(const Duration(milliseconds: 200));
        await phrase('물 좀 주세요');
        expect(cubit.state.segments, hasLength(1));
        now = now.add(const Duration(seconds: 2));
        await phrase('물 좀 주세요');
        expect(cubit.state.segments, hasLength(2));
      },
    );
    blocTest<LiveSessionCubit, LiveSessionState>(
      'keeps short real utterances instead of deleting them as substrings',
      build: build,
      act: (cubit) async {
        await listen(cubit);
        await phrase('물 좀 주세요');
        await signal(SegmentStarted(Uint8List(3200)));
        stream.opened.last.controller.add(const LiveInterim('물'));
        await pumpEventQueue();
        expect(cubit.state.segments.last.text, '물');
        stream.opened.last.controller.add(const LiveInterim('네'));
        await pumpEventQueue();
        expect(cubit.state.segments.last.text, '네');
      },
    );
    blocTest<LiveSessionCubit, LiveSessionState>(
      'hides replacement characters and never plays a corrupted final',
      build: build,
      act: (cubit) async {
        await listen(cubit);
        await signal(SegmentStarted(Uint8List(3200)));
        stream.opened.last.controller.add(const LiveInterim('물� 주세요'));
        await pumpEventQueue();
        expect(cubit.state.segments.last.text, '물 주세요');
        await signal(SegmentEnded(Uint8List(3200), kept: true));
        stream.opened.last.finish(
          const LiveFinal(
            Transcription(
              traceId: 'broken',
              finalTranscript: '물� 주세요',
              asrConfidence: 0.9,
            ),
          ),
        );
        await pumpEventQueue();
        expect(
          cubit.state.segments.single.status,
          LiveSegmentStatus.unclear,
        );
        verifyNoSpeech();
        await Future<void>.delayed(const Duration(milliseconds: 1050));
        verifyNoSpeech();
      },
    );
    blocTest<LiveSessionCubit, LiveSessionState>(
      'does not speak or log a low confidence result',
      build: build,
      act: (cubit) async {
        await listen(cubit);
        await signal(SegmentStarted(Uint8List(3200)));
        await signal(SegmentEnded(Uint8List(3200), kept: true));
        stream.opened.last.finish(const LiveUnclear());
        await pumpEventQueue();
        expect(cubit.state.segments.single.status, LiveSegmentStatus.unclear);
        verifyNoSpeech();
      },
    );
    blocTest<LiveSessionCubit, LiveSessionState>(
      'does not play or log a final below the confidence threshold',
      build: build,
      act: (cubit) async {
        await listen(cubit);
        await signal(SegmentStarted(Uint8List(3200)));
        await signal(SegmentEnded(Uint8List(3200), kept: true));
        stream.opened.last.finish(
          const LiveFinal(
            Transcription(
              traceId: 'low',
              finalTranscript: '물 주세요',
              asrConfidence: 0.3,
            ),
          ),
        );
        await pumpEventQueue();
        expect(cubit.state.segments.single.status, LiveSegmentStatus.unclear);
        verifyNoSpeech();
        verifyNever(
          () => repository.bypass(any(), latency: any(named: 'latency')),
        );
      },
    );
    blocTest<LiveSessionCubit, LiveSessionState>(
      'stop cancels queued playback and all outstanding socket sessions',
      build: build,
      act: (cubit) async {
        await listen(cubit);
        await phrase('책상');
        await phrase('다음 문장');
        await signal(SegmentStarted(Uint8List(3200)));
        await cubit.stop();
        await Future<void>.delayed(const Duration(milliseconds: 1050));
        expect(stream.opened.last.cancelled, isTrue);
        expect(cubit.state.status, LiveStatus.closed);
        verifySpeech('책상');
        verifyNever(
          () => tts.speakWithPlayback(
            '다음 문장',
            onStarted: any(named: 'onStarted'),
            onEnded: any(named: 'onEnded'),
          ),
        );
      },
    );
    blocTest<LiveSessionCubit, LiveSessionState>(
      'surfaces microphone permission failure',
      setUp: () =>
          when(mic.start).thenThrow(const PermissionFailure(permanent: true)),
      build: build,
      act: (cubit) => cubit.start(),
      expect: () => [
        isA<LiveSessionState>().having(
          (s) => s.status,
          'status',
          LiveStatus.failed,
        ),
        isA<LiveSessionState>().having(
          (s) => s.status,
          'status',
          LiveStatus.closed,
        ),
      ],
    );
  });
}
