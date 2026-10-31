import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/tts/tts_voice.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';
import 'package:marieum_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:marieum_app/features/settings/presentation/widgets/voice_picker_sheet.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/presentation/cubit/playback_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/pump_app.dart';

class _MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _MockPlaybackCubit extends MockCubit<PlaybackState>
    implements PlaybackCubit {}

void main() {
  group(VoicePickerSheet, () {
    late _MockSettingsCubit settings;
    const voice = TtsVoice(
      id: 'voice-id',
      name: '한국어 목소리',
      locale: 'ko-KR',
      quality: TtsVoiceQuality.enhanced,
      requiresNetwork: true,
    );

    setUp(() {
      settings = _MockSettingsCubit();
      whenListen(
        settings,
        const Stream<SettingsState>.empty(),
        initialState: const SettingsState(AppSettings(), voices: [voice]),
      );
      when(settings.loadVoices).thenAnswer((_) async {});
      when(() => settings.setVoice(any())).thenAnswer((_) async {});
    });

    testWidgets('opens a sheet with names, quality and network labels', (
      tester,
    ) async {
      await tester.pumpApp(
        initialLocation: '/settings',
        settingsCubit: settings,
      );
      await tester.tap(find.text('목소리'));
      await tester.pumpAndSettle();
      expect(find.byType(VoicePickerSheet), findsOneWidget);
      expect(find.text(voice.name), findsOneWidget);
      expect(find.text('고품질 · 인터넷 필요'), findsOneWidget);
      verify(settings.loadVoices).called(1);
      await tester.tap(find.text(voice.name));
      await tester.pumpAndSettle();
      verify(() => settings.setVoice(voice.id)).called(1);
      expect(find.byType(VoicePickerSheet), findsNothing);
    });

    testWidgets('allows returning to automatic selection', (tester) async {
      whenListen(
        settings,
        const Stream<SettingsState>.empty(),
        initialState: const SettingsState(
          AppSettings(voiceId: 'voice-id'),
          voices: [voice],
        ),
      );
      await tester.pumpApp(
        initialLocation: '/settings',
        settingsCubit: settings,
      );
      await tester.tap(find.text('목소리'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('자동(추천)'));
      await tester.pumpAndSettle();
      verify(() => settings.setVoice(null)).called(1);
    });

    testWidgets('previews through the existing playback route without saving', (
      tester,
    ) async {
      when(() => settings.previewVoice(any(), any())).thenAnswer((call) {
        final play = call.positionalArguments[1] as Future<void> Function();
        return play();
      });
      PlaybackRequest? received;
      final router = await tester.pumpApp(
        initialLocation: '/settings',
        settingsCubit: settings,
        createPlaybackCubit: (request) {
          received = request;
          final playback = _MockPlaybackCubit();
          whenListen(
            playback,
            const Stream<PlaybackState>.empty(),
            initialState: PlaybackState(
              text: request.text,
              status: PlaybackStatus.playing,
            ),
          );
          when(playback.start).thenAnswer((_) async {});
          when(playback.close).thenAnswer((_) async {});
          return playback;
        },
      );
      await tester.tap(find.text('목소리'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('미리듣기').last);
      await tester.pumpAndSettle();
      expect(received?.origin, PlaybackOrigin.preview);
      expect(received?.text, '미지근한 물 주세요');
      verify(() => settings.previewVoice(voice.id, any())).called(1);
      verifyNever(() => settings.setVoice(any()));
      router.pop();
      await tester.pumpAndSettle();
    });

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets(
        'shows the installation guide for $platform without quality voices',
        (
          tester,
        ) async {
          whenListen(
            settings,
            const Stream<SettingsState>.empty(),
            initialState: const SettingsState(AppSettings(), voices: []),
          );
          await tester.pumpApp(
            initialLocation: '/settings',
            settingsCubit: settings,
          );
          await tester.tap(find.text('목소리'));
          await tester.pumpAndSettle();
          expect(
            find.text(
              platform == TargetPlatform.iOS
                  ? '설정 > 손쉬운 사용 > 읽기 및 말하기 > 음성 > 한국어에서 '
                        '고품질 음성을 내려받으면 더 자연스러워요'
                  : 'Google 음성 서비스를 설치하거나 업데이트하면 더 자연스러운 목소리를 쓸 수 있어요',
            ),
            findsOneWidget,
          );
        },
        variant: TargetPlatformVariant({platform}),
      );
    }
  });
}
