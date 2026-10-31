import 'dart:async';
import 'dart:typed_data';

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

class _MockTts extends Mock implements TtsPort {}

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
  late _MockMic mic;
  late _FakeStream stream;
  late _MockRepository repository;
  late _MockTts tts;
  late _MockSegmenter segmenter;
  late StreamController<Uint8List> input;
  late Completer<Result<void>> speaking;

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
    input = StreamController<Uint8List>();
    speaking = Completer();
    when(mic.start).thenAnswer((_) async => input.stream);
    when(mic.stop).thenAnswer((_) async {});
    when(mic.dispose).thenAnswer((_) async {});
    when(() => tts.speak(any())).thenAnswer((_) => speaking.future);
    when(tts.stop).thenAnswer((_) async => const Success(null));
    when(
      () => repository.bypass(any(), latency: any(named: 'latency')),
    ).thenAnswer((_) async => const Success('물 좀 주세요'));
    when(() => segmenter.hearing).thenReturn(false);
    when(() => segmenter.threshold).thenReturn(0.35);
    when(segmenter.reset).thenReturn(null);
  });

  LiveSessionCubit build() => LiveSessionCubit(
    mic: mic,
    stream: stream,
    repository: repository,
    tts: tts,
    segmenter: segmenter,
  );

  Future<void> signal(SegmentSignal? next) async {
    when(
      () => segmenter.add(any(), level: any(named: 'level')),
    ).thenReturn(next);
    input.add(Uint8List(3200));
    await pumpEventQueue();
  }

  Future<_FakeUtterance> speakOnce() async {
    await signal(SegmentStarted(Uint8List(12800)));
    await signal(SegmentContinued(Uint8List(3200)));
    await signal(SegmentEnded(Uint8List(3200), kept: true));
    return stream.opened.last;
  }

  group(LiveSessionCubit, () {
    test(
      'streams speech, shows interim text, speaks and logs the final',
      () async {
        final cubit = build();
        addTearDown(cubit.close);
        await cubit.start();
        expect(cubit.state.status, LiveStatus.listening);

        await signal(SegmentStarted(Uint8List(12800)));
        final utterance = stream.opened.single;
        utterance.controller.add(const LiveInterim('물 좀'));
        await pumpEventQueue();
        expect(
          cubit.state.segments.single.status,
          LiveSegmentStatus.interpreting,
        );
        expect(cubit.state.segments.single.text, '물 좀');

        await signal(SegmentEnded(Uint8List(3200), kept: true));
        expect(utterance.audio, hasLength(16000));
        expect(utterance.ended, isTrue);

        utterance.finish(const LiveFinal(_clear));
        await pumpEventQueue();
        expect(cubit.state.segments.single.status, LiveSegmentStatus.done);
        expect(cubit.state.playing, isTrue);
        verify(() => tts.speak('물 좀 주세요')).called(1);
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

    test('drops speech heard while the app is speaking', () async {
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.start();
      (await speakOnce()).finish(const LiveFinal(_clear));
      await pumpEventQueue();
      expect(cubit.state.playing, isTrue);

      await signal(null);
      verify(segmenter.reset).called(1);
      expect(stream.opened, hasLength(1));
      speaking.complete(const Success(null));
    });

    test('cancels a click too short to be speech', () async {
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.start();
      await signal(SegmentStarted(Uint8List(3200)));
      stream.opened.single.controller.add(const LiveInterim('어'));
      await pumpEventQueue();
      await signal(SegmentEnded(Uint8List(3200), kept: false));
      expect(stream.opened.single.cancelled, isTrue);
      expect(cubit.state.segments, isEmpty);
    });

    test('marks unclear speech without speaking', () async {
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.start();
      (await speakOnce()).finish(const LiveUnclear());
      await pumpEventQueue();
      expect(cubit.state.segments.single.status, LiveSegmentStatus.unclear);
      verifyNever(() => tts.speak(any()));
      verifyNever(
        () => repository.bypass(any(), latency: any(named: 'latency')),
      );
    });

    test('keeps listening when one utterance fails', () async {
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.start();
      (await speakOnce()).finish(const LiveFailed(NetworkFailure()));
      await pumpEventQueue();
      expect(cubit.state.segments.single.status, LiveSegmentStatus.failed);
      expect(cubit.state.status, LiveStatus.listening);
    });

    test('shows a failure when the microphone is denied', () async {
      when(mic.start).thenThrow(const PermissionFailure(permanent: true));
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.start();
      expect(cubit.state.status, LiveStatus.failed);
      expect(cubit.state.failure, isA<PermissionFailure>());
    });

    test(
      'stop cancels the stream, closes the mic and silences speech',
      () async {
        final cubit = build();
        addTearDown(cubit.close);
        await cubit.start();
        await signal(SegmentStarted(Uint8List(3200)));
        await cubit.stop();
        expect(stream.opened.single.cancelled, isTrue);
        verify(mic.stop).called(1);
        verify(tts.stop).called(1);
        expect(cubit.state.status, LiveStatus.closed);
      },
    );
  });
}
