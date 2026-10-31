import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/mic_stream.dart';
import 'package:marieum_app/core/audio/recorded_audio.dart';
import 'package:marieum_app/core/audio/speech_segmenter.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:marieum_app/features/speak/domain/repositories/utterance_repository.dart';
import 'package:marieum_app/features/speak/presentation/cubit/live_session_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockMic extends Mock implements MicStream {}

class _MockRepository extends Mock implements UtteranceRepository {}

class _MockTts extends Mock implements TtsPort {}

class _MockSegmenter extends Mock implements SpeechSegmenter {}

const _clear = Transcription(
  traceId: 't1',
  finalTranscript: '물 좀 주세요',
  asrConfidence: 0.9,
);
const _unclear = Transcription(
  traceId: 't2',
  finalTranscript: '무ㅏ',
  asrConfidence: 0.2,
);

void main() {
  late _MockMic mic;
  late _MockRepository repository;
  late _MockTts tts;
  late _MockSegmenter segmenter;
  late StreamController<Uint8List> input;
  late Completer<Result<void>> speaking;

  setUpAll(() {
    registerFallbackValue(RecordedAudio(bytes: Uint8List(0), durationMs: 0));
    registerFallbackValue(_clear);
    registerFallbackValue(Duration.zero);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mic = _MockMic();
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
    when(() => segmenter.hearing).thenReturn(false);
    when(segmenter.reset).thenReturn(null);
    when(
      () => segmenter.add(any(), level: any(named: 'level')),
    ).thenReturn(null);
  });

  LiveSessionCubit build() => LiveSessionCubit(
    mic: mic,
    repository: repository,
    tts: tts,
    segmenter: segmenter,
  );

  void segmentNext() => when(
    () => segmenter.add(any(), level: any(named: 'level')),
  ).thenReturn(Uint8List(3200));

  group(LiveSessionCubit, () {
    test('interprets a segment, shows it and speaks it', () async {
      when(
        () => repository.transcribe(any()),
      ).thenAnswer((_) async => const Success(_clear));
      when(
        () => repository.bypass(any(), latency: any(named: 'latency')),
      ).thenAnswer((_) async => const Success('물 좀 주세요'));
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.start();
      expect(cubit.state.status, LiveStatus.listening);

      segmentNext();
      input.add(Uint8List(3200));
      await pumpEventQueue();
      expect(cubit.state.segments.single.status, LiveSegmentStatus.done);
      expect(cubit.state.segments.single.text, '물 좀 주세요');
      expect(cubit.state.playing, isTrue);
      verify(() => tts.speak('물 좀 주세요')).called(1);

      input.add(Uint8List(3200));
      await pumpEventQueue();
      verify(segmenter.reset).called(1);
      expect(cubit.state.segments, hasLength(1));

      speaking.complete(const Success(null));
      await pumpEventQueue();
      expect(cubit.state.playing, isFalse);
    });

    test('marks unclear speech without speaking', () async {
      when(
        () => repository.transcribe(any()),
      ).thenAnswer((_) async => const Success(_unclear));
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.start();
      segmentNext();
      input.add(Uint8List(3200));
      await pumpEventQueue();
      expect(cubit.state.segments.single.status, LiveSegmentStatus.unclear);
      verifyNever(() => tts.speak(any()));
      verifyNever(
        () => repository.bypass(any(), latency: any(named: 'latency')),
      );
    });

    test('keeps listening when one segment fails', () async {
      when(
        () => repository.transcribe(any()),
      ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.start();
      segmentNext();
      input.add(Uint8List(3200));
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

    test('stop closes the microphone and silences speech', () async {
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.start();
      await cubit.stop();
      verify(mic.stop).called(1);
      verify(tts.stop).called(1);
      expect(cubit.state.status, LiveStatus.closed);
    });
  });
}
