import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/recorder.dart';
import 'package:marieum_app/core/audio/recording_engine.dart';
import 'package:marieum_app/core/audio/voice_audio_session.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:mocktail/mocktail.dart';

class _MockEngine extends Mock implements RecordingEngine {}

class _MockPermission extends Mock implements MicrophonePermission {}

class _MockSession extends Mock implements VoiceAudioSession {}

class _MockTimer extends Mock implements Timer {}

void main() {
  group(Recorder, () {
    late _MockEngine engine;
    late _MockPermission permission;
    late _MockSession session;
    late StreamController<List<int>> source;
    late Recorder recorder;
    late void Function() deadline;
    late Duration timeout;

    setUp(() {
      engine = _MockEngine();
      permission = _MockPermission();
      session = _MockSession();
      source = StreamController<List<int>>();
      when(
        () => permission.request(),
      ).thenAnswer((_) async => MicrophoneAccess.granted);
      when(() => session.configure()).thenAnswer((_) async {});
      when(() => engine.startStream()).thenAnswer((_) async => source.stream);
      when(() => engine.stop()).thenAnswer((_) async {
        await source.close();
      });
      when(() => engine.dispose()).thenAnswer((_) async {});
      recorder = Recorder(
        engine: engine,
        permission: permission,
        audioSession: session,
        createTimer: (duration, callback) {
          timeout = duration;
          deadline = callback;
          return _MockTimer();
        },
      );
    });
    tearDown(() async {
      await recorder.dispose();
    });

    for (final chunkSize in [1, 31, 4096, 9000]) {
      test(
        'collects platform chunks of $chunkSize bytes into one WAV',
        () async {
          final pcm = List.generate(6400, (i) => i % 256);
          await recorder.start();
          for (var i = 0; i < pcm.length; i += chunkSize) {
            source.add(
              pcm.sublist(
                i,
                i + chunkSize < pcm.length ? i + chunkSize : pcm.length,
              ),
            );
          }
          final audio = await recorder.stop();
          expect(audio.bytes.sublist(44), pcm);
          expect(audio.durationMs, 200);
          verify(() => engine.stop()).called(1);
        },
      );
    }
    test(
      'automatically stops and truncates audio at ten seconds of samples',
      () async {
        await recorder.start();
        source.add(List.filled(320100, 7));
        final audio = await recorder.completed;
        expect(audio.durationMs, 10000);
        expect(audio.bytes.length, 320044);
        expect(audio.bytes.sublist(44), List.filled(320000, 7));
        verify(() => engine.stop()).called(1);
      },
    );
    test(
      'stops at the ten second deadline even when no samples arrive',
      () async {
        await recorder.start();
        expect(timeout, const Duration(seconds: 10));
        deadline();
        expect((await recorder.completed).durationMs, 0);
        verify(() => engine.stop()).called(1);
      },
    );
    for (final access in [
      MicrophoneAccess.denied,
      MicrophoneAccess.permanent,
    ]) {
      test(
        'reports $access as a typed permission failure without recording',
        () async {
          when(() => permission.request()).thenAnswer((_) async => access);
          await expectLater(
            recorder.start(),
            throwsA(
              isA<PermissionFailure>().having(
                (failure) => failure.permanent,
                'permanent',
                access == MicrophoneAccess.permanent,
              ),
            ),
          );
          verifyNever(() => engine.startStream());
        },
      );
    }
    test(
      'preserves capture errors and still stops the native recorder',
      () async {
        await recorder.start();
        source.addError(Exception('capture error'));
        await expectLater(recorder.stop(), throwsException);
        verify(() => engine.stop()).called(1);
      },
    );
    test(
      'disposal during permission acquisition never starts the microphone',
      () async {
        final pending = Completer<MicrophoneAccess>();
        when(() => permission.request()).thenAnswer((_) => pending.future);
        final starting = recorder.start();
        final expectation = expectLater(starting, throwsStateError);
        final disposal = recorder.dispose();
        pending.complete(MicrophoneAccess.granted);
        await expectation;
        await disposal;
        verifyNever(() => engine.startStream());
        verify(() => engine.dispose()).called(1);
      },
    );
  });
}
