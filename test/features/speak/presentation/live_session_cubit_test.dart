import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/mic_stream.dart';
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
  @override
  Stream<LiveEvent> get events => server.stream;
  @override
  void add(Uint8List audio) {}
  @override
  Future<void> close() => server.close();
}

class _FakeStream implements LiveStream {
  final conversation = _FakeConversation();
  @override
  LiveConversation connect() => conversation;
}

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
    late StreamController<Uint8List> input;
    late DateTime now;
    late LiveSessionCubit cubit;

    setUp(() async {
      mic = _MockMic();
      repository = _MockRepository();
      tts = _MockTts();
      stream = _FakeStream();
      input = StreamController<Uint8List>();
      now = DateTime(2026, 11, 20, 12);
      when(mic.start).thenAnswer((_) async => input.stream);
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
        now: () => now,
      );
      await cubit.start();
      now = now.add(LiveSessionCubit.warmUp);
      input.add(Uint8List(3200));
      await pumpEventQueue();
    });

    tearDown(() => cubit.close());

    test('speaks a sentence however low its confidence', () async {
      stream.conversation.server.add(LiveFinal(_heard('물 주세요', 0.2)));
      await pumpEventQueue();

      expect(cubit.state.segments.single.status, LiveSegmentStatus.done);
      verify(
        () => tts.speakWithPlayback(
          '물 주세요',
          onStarted: any(named: 'onStarted'),
          onEnded: any(named: 'onEnded'),
        ),
      ).called(1);
    });

    test('still does not speak a sentence with broken letters', () async {
      stream.conversation.server.add(LiveFinal(_heard('물 �세요', 0.95)));
      await pumpEventQueue();

      expect(cubit.state.segments.single.status, LiveSegmentStatus.unclear);
      verifyNever(
        () => tts.speakWithPlayback(
          any(),
          onStarted: any(named: 'onStarted'),
          onEnded: any(named: 'onEnded'),
        ),
      );
    });
  });
}
