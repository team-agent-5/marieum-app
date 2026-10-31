import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/tts/tts_engine.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlugin extends Mock implements FlutterTts {}

void main() {
  group(FlutterTtsEngine, () {
    late _MockPlugin plugin;
    late FlutterTtsEngine engine;
    late void Function() completed;
    setUpAll(() {
      registerFallbackValue(() {});
    });
    setUp(() {
      plugin = _MockPlugin();
      when(() => plugin.setCompletionHandler(any())).thenAnswer((call) {
        completed = call.positionalArguments.first as void Function();
      });
      when(() => plugin.speak(any())).thenAnswer((_) async => 1);
      when(() => plugin.stop()).thenAnswer((_) async => 1);
      when(() => plugin.awaitSpeakCompletion(false)).thenAnswer((_) async => 1);
      when(
        () => plugin.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playAndRecord,
          [
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          ],
        ),
      ).thenAnswer((_) async => 1);
      when(() => plugin.setLanguage('ko-KR')).thenAnswer((_) async => 1);
      when(() => plugin.setSpeechRate(0.5)).thenAnswer((_) async => 1);
      when(() => plugin.setVolume(0.8)).thenAnswer((_) async => 1);
      engine = FlutterTtsEngine(platform: VoicePlatform.ios, plugin: plugin);
    });
    test(
      'waits for the native completion callback after dispatch',
      () async {
        var finished = false;
        final speaking = engine.speak('안녕하세요').then((_) {
          finished = true;
        });
        await Future<void>.delayed(Duration.zero);
        expect(finished, isFalse);
        completed();
        await speaking;
        expect(finished, isTrue);
      },
    );
    test(
      'stopping settles the pending speech without requiring a native callback',
      () async {
        final speaking = engine.speak('안녕하세요');
        final failure = expectLater(speaking, throwsA(isA<TtsFailure>()));
        await engine.stop();
        await failure;
      },
    );
    test(
      'matches speaker and Bluetooth audio session options',
      () async {
        await engine.configure(rate: 0.5, volume: 0.8);
        verify(
          () => plugin.setIosAudioCategory(
            IosTextToSpeechAudioCategory.playAndRecord,
            [
              IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
              IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            ],
          ),
        ).called(1);
        verify(() => plugin.setLanguage('ko-KR')).called(1);
      },
    );
  });
}
