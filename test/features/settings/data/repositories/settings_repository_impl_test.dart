import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/settings/data/datasources/settings_mirror.dart';
import 'package:marieum_app/features/settings/data/dto/settings_payload.dart';
import 'package:marieum_app/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockMirror extends Mock implements SettingsMirror {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(const AppSettings()));
  group(SettingsRepositoryImpl, () {
    late PrefsStore prefs;
    late _MockMirror mirror;
    late List<AppSettings> applied;
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.ttsRate: 'fast',
        PrefsKeys.ttsVolume: 'soft',
        PrefsKeys.largeText: true,
      });
      prefs = PrefsStore(
        SharedPrefsBackend(await SharedPreferences.getInstance()),
      );
      mirror = _MockMirror();
      applied = [];
      when(
        () => mirror.send(any()),
      ).thenAnswer((_) async => const Success(null));
    });
    test('loads local values and applies voice settings at construction', () {
      final repository = SettingsRepositoryImpl(
        prefs: prefs,
        mirror: mirror,
        applyVoice: applied.add,
      );
      expect(
        repository.initial,
        const AppSettings(
          rate: TtsRate.fast,
          volume: TtsVolume.soft,
          largeText: true,
        ),
      );
      expect(applied, [repository.initial]);
    });
    test('stores app names and maps only the server volume names', () async {
      final repository = SettingsRepositoryImpl(
        prefs: prefs,
        mirror: mirror,
        applyVoice: applied.add,
      );
      const settings = AppSettings(volume: TtsVolume.loud);
      await repository.save(settings);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.readString(PrefsKeys.ttsVolume), 'loud');
      expect(settingsPayload(settings)['tts_volume'], 'high');
      expect(
        settingsPayload(
          const AppSettings(volume: TtsVolume.soft),
        )['tts_volume'],
        'low',
      );
      verify(() => mirror.send(settings)).called(1);
    });
    test('does not wait for or surface a failed mirror', () async {
      final pending = Completer<Result<void>>();
      when(() => mirror.send(any())).thenAnswer((_) => pending.future);
      final repository = SettingsRepositoryImpl(
        prefs: prefs,
        mirror: mirror,
        applyVoice: applied.add,
      );
      expect(await repository.save(const AppSettings()), isA<Success<void>>());
      pending.complete(const FailureResult(NetworkFailure()));
      await Future<void>.delayed(Duration.zero);
      expect(prefs.readString(PrefsKeys.ttsRate), 'normal');
      expect(applied.last, const AppSettings());
    });
    test(
      'ignores thrown mirror failures and preserves ordered local writes',
      () async {
        when(() => mirror.send(any())).thenThrow(Exception('offline'));
        final repository = SettingsRepositoryImpl(
          prefs: prefs,
          mirror: mirror,
          applyVoice: applied.add,
        );
        await Future.wait([
          repository.save(const AppSettings(rate: TtsRate.slow)),
          repository.save(const AppSettings(rate: TtsRate.fast)),
        ]);
        await Future<void>.delayed(Duration.zero);
        expect(prefs.readString(PrefsKeys.ttsRate), 'fast');
      },
    );
    test(
      'persists a voice only locally and restores it through applyVoice',
      () async {
        final repository = SettingsRepositoryImpl(
          prefs: prefs,
          mirror: mirror,
          applyVoice: applied.add,
        );
        const settings = AppSettings(voiceId: 'ko-voice-id');
        expect(await repository.save(settings), isA<Success<void>>());
        expect(prefs.readString(PrefsKeys.ttsVoiceId), 'ko-voice-id');
        final restored = SettingsRepositoryImpl(
          prefs: prefs,
          mirror: mirror,
          applyVoice: applied.add,
        );
        expect(restored.initial.voiceId, 'ko-voice-id');
        expect(applied.last.voiceId, 'ko-voice-id');
        expect(settingsPayload(settings), {
          'tts_rate': 'normal',
          'tts_volume': 'normal',
          'large_text': false,
        });
        await repository.save(settings.copyWith(voiceId: null));
        expect(prefs.readString(PrefsKeys.ttsVoiceId), isNull);
        final auto = SettingsRepositoryImpl(
          prefs: prefs,
          mirror: mirror,
          applyVoice: applied.add,
        );
        expect(auto.initial.voiceId, isNull);
      },
    );

    test('preserves a selected voice when unrelated settings change', () async {
      const settings = AppSettings(voiceId: 'ko-voice-id');
      expect(settings.copyWith(rate: TtsRate.fast).voiceId, 'ko-voice-id');
      expect(settings.copyWith(largeText: true).voiceId, 'ko-voice-id');
      expect(settings.copyWith(voiceId: null).voiceId, isNull);
    });
  });
}
