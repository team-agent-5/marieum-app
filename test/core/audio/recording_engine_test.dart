import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/recording_engine.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';

class _MockPlugin extends Mock implements AudioRecorder {}

void main() {
  group(PlatformRecordingEngine, () {
    setUpAll(() {
      registerFallbackValue(const RecordConfig());
    });
    test('only starts a PCM16 16kHz mono memory stream', () async {
      final plugin = _MockPlugin();
      when(
        () => plugin.startStream(any()),
      ).thenAnswer((_) async => const Stream<Uint8List>.empty());
      final engine = PlatformRecordingEngine(plugin: plugin);
      await engine.startStream();
      final config =
          verify(() => plugin.startStream(captureAny())).captured.single
              as RecordConfig;
      expect(config.encoder, AudioEncoder.pcm16bits);
      expect(config.sampleRate, 16000);
      expect(config.numChannels, 1);
      expect(config.echoCancel, isFalse);
      expect(config.autoGain, isFalse);
      expect(config.noiseSuppress, isFalse);
    });
  });
}
