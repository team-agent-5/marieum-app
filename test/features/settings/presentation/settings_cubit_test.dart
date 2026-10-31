import 'dart:async';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/settings/domain/app_settings.dart';
import 'package:marieum_app/features/settings/presentation/settings_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements SettingsRepository {}

void main() {
  setUpAll(() => registerFallbackValue(const AppSettings()));
  group(SettingsCubit, () {
    late _MockRepository repository;
    setUp(() {
      repository = _MockRepository();
      when(
        () => repository.initial,
      ).thenReturn(const AppSettings(rate: TtsRate.slow));
      when(
        () => repository.save(any()),
      ).thenAnswer((_) async => const Success(null));
    });
    blocTest<SettingsCubit, SettingsState>(
      'starts from persisted settings without a loading state',
      build: () => SettingsCubit(repository),
      verify: (cubit) => expect(cubit.state.settings.rate, TtsRate.slow),
    );
    blocTest<SettingsCubit, SettingsState>(
      'saves rate, volume and large text changes',
      build: () => SettingsCubit(repository),
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
      build: () => SettingsCubit(repository),
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
      build: () => SettingsCubit(repository),
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
  });
}
