import 'dart:async';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/core/tts/tts_voice.dart';
import 'package:marieum_app/core/tts/tts_voice_selector.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';
import 'package:marieum_app/features/settings/domain/repositories/settings_repository.dart';
import 'package:marieum_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockVoices extends Mock implements TtsVoiceSelector {}

class _MockRepository extends Mock implements SettingsRepository {}

void main() {
  setUpAll(() => registerFallbackValue(const AppSettings()));
  group(SettingsCubit, () {
    late _MockRepository repository;
    late _MockVoices voices;
    setUp(() {
      repository = _MockRepository();
      voices = _MockVoices();
      when(voices.availableVoices).thenAnswer((_) async => []);
      when(() => voices.selectVoice(any())).thenAnswer((_) async {});
      when(
        () => repository.initial,
      ).thenReturn(const AppSettings(rate: TtsRate.slow));
      when(
        () => repository.save(any()),
      ).thenAnswer((_) async => const Success(null));
    });
    blocTest<SettingsCubit, SettingsState>(
      'starts from persisted settings without a loading state',
      build: () => SettingsCubit(repository, voices: voices),
      verify: (cubit) => expect(cubit.state.settings.rate, TtsRate.slow),
    );
    blocTest<SettingsCubit, SettingsState>(
      'saves rate, volume and large text changes',
      build: () => SettingsCubit(repository, voices: voices),
      act: (cubit) async {
        await cubit.setRate(TtsRate.fast);
        await cubit.setVolume(TtsVolume.loud);
        await cubit.setLargeText(value: true);
      },
      expect: () => [
        const SettingsState(AppSettings(rate: TtsRate.fast)),
        const SettingsState(
          AppSettings(rate: TtsRate.fast, volume: TtsVolume.loud),
        ),
        const SettingsState(
          AppSettings(
            rate: TtsRate.fast,
            volume: TtsVolume.loud,
            largeText: true,
          ),
        ),
      ],
    );
    blocTest<SettingsCubit, SettingsState>(
      'keeps the displayed value when local persistence fails',
      setUp: () => when(
        () => repository.save(any()),
      ).thenAnswer((_) async => const FailureResult(StorageFailure())),
      build: () => SettingsCubit(repository, voices: voices),
      act: (cubit) => cubit.setVolume(TtsVolume.soft),
      expect: () => [
        const SettingsState(
          AppSettings(rate: TtsRate.slow, volume: TtsVolume.soft),
        ),
        isA<SettingsState>().having(
          (s) => (s.settings.volume, s.failure.runtimeType),
          'retained setting and error',
          (TtsVolume.soft, StorageFailure),
        ),
      ],
    );
    blocTest<SettingsCubit, SettingsState>(
      'ignores an old save failure after a newer choice',
      build: () => SettingsCubit(repository, voices: voices),
      act: (cubit) async {
        final first = Completer<Result<void>>();
        when(
          () => repository.save(const AppSettings(rate: TtsRate.fast)),
        ).thenAnswer((_) => first.future);
        final pending = cubit.setRate(TtsRate.fast);
        await cubit.setRate(TtsRate.normal);
        first.complete(const FailureResult(StorageFailure()));
        await pending;
      },
      expect: () => [
        const SettingsState(AppSettings(rate: TtsRate.fast)),
        const SettingsState(AppSettings()),
      ],
    );
    blocTest<SettingsCubit, SettingsState>(
      'stores a specific voice and can explicitly return '
      'to automatic selection',
      build: () => SettingsCubit(repository, voices: voices),
      act: (cubit) async {
        await cubit.setVoice('선택');
        await cubit.setRate(TtsRate.fast);
        await cubit.setVoice(null);
      },
      expect: () => [
        const SettingsState(AppSettings(rate: TtsRate.slow, voiceId: '선택')),
        const SettingsState(AppSettings(rate: TtsRate.fast, voiceId: '선택')),
        const SettingsState(AppSettings(rate: TtsRate.fast)),
      ],
      verify: (_) => verify(
        () => repository.save(
          const AppSettings(rate: TtsRate.slow, voiceId: '선택'),
        ),
      ).called(1),
    );
    blocTest<SettingsCubit, SettingsState>(
      'loads voices once and retains the list after a setting changes',
      build: () => SettingsCubit(repository, voices: voices),
      act: (cubit) async {
        await cubit.loadVoices();
        await cubit.loadVoices();
        await cubit.setVoice('선택');
      },
      expect: () => [
        const SettingsState(AppSettings(rate: TtsRate.slow), voices: []),
        const SettingsState(
          AppSettings(rate: TtsRate.slow, voiceId: '선택'),
          voices: [],
        ),
      ],
      verify: (_) => verify(voices.availableVoices).called(1),
    );
    blocTest<SettingsCubit, SettingsState>(
      'keeps settings and shows an empty voice list if enumeration fails',
      setUp: () =>
          when(voices.availableVoices).thenThrow(Exception('unsupported')),
      build: () => SettingsCubit(repository, voices: voices),
      act: (cubit) => cubit.loadVoices(),
      expect: () => [
        const SettingsState(AppSettings(rate: TtsRate.slow), voices: []),
      ],
    );
    blocTest<SettingsCubit, SettingsState>(
      'previews a voice without persisting it and restores the saved selection',
      setUp: () => when(
        () => repository.initial,
      ).thenReturn(const AppSettings(voiceId: '저장')),
      build: () => SettingsCubit(repository, voices: voices),
      act: (cubit) => cubit.previewVoice('미리듣기', () async {
        verify(() => voices.selectVoice('미리듣기')).called(1);
      }),
      expect: () => <SettingsState>[],
      verify: (_) {
        verify(() => voices.selectVoice('저장')).called(1);
        verifyNever(() => repository.save(any()));
      },
    );
    blocTest<SettingsCubit, SettingsState>(
      'restores automatic selection even if the preview route fails',
      build: () => SettingsCubit(repository, voices: voices),
      act: (cubit) async {
        await expectLater(
          cubit.previewVoice('선택', () async => throw StateError('route')),
          throwsStateError,
        );
      },
      expect: () => <SettingsState>[],
      verify: (_) => verify(() => voices.selectVoice(null)).called(1),
    );
    blocTest<SettingsCubit, SettingsState>(
      'ignores voice loading after disposal',
      build: () => SettingsCubit(repository, voices: voices),
      act: (cubit) async {
        final result = Completer<List<TtsVoice>>();
        when(voices.availableVoices).thenAnswer((_) => result.future);
        final loading = cubit.loadVoices();
        await cubit.close();
        result.complete([]);
        await loading;
      },
      expect: () => <SettingsState>[],
    );
  });
}
