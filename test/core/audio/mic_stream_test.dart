import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/mic_stream.dart';
import 'package:marieum_app/core/audio/recording_engine.dart';
import 'package:marieum_app/core/audio/voice_audio_session.dart';
import 'package:mocktail/mocktail.dart';

class _MockEngine extends Mock implements RecordingEngine {}

class _MockPermission extends Mock implements MicrophonePermission {}

class _MockSession extends Mock implements VoiceAudioSession {}

void main() {
  group(MicStream, () {
    late _MockEngine engine;
    late _MockPermission permission;
    late _MockSession session;
    late MicStream mic;
    setUp(() {
      engine = _MockEngine();
      permission = _MockPermission();
      session = _MockSession();
      when(
        permission.request,
      ).thenAnswer((_) async => MicrophoneAccess.granted);
      when(session.configure).thenAnswer((_) async {});
      when(
        () => engine.startStream(echoCancel: any(named: 'echoCancel')),
      ).thenAnswer((_) async => const Stream.empty());
      when(engine.stop).thenAnswer((_) async {});
      mic = MicStream(
        engine: engine,
        permission: permission,
        audioSession: session,
      );
    });
    test('starts the stream with echo cancellation', () async {
      await mic.start();
      verify(() => engine.startStream(echoCancel: true)).called(1);
      await mic.stop();
      verify(engine.stop).called(1);
    });
  });
}
