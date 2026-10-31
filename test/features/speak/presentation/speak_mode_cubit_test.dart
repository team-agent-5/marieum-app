import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/features/speak/data/datasources/speak_preferences_data_source.dart';
import 'package:marieum_app/features/speak/data/repositories/speak_mode_repository_impl.dart';
import 'package:marieum_app/features/speak/domain/entities/speak_mode.dart';
import 'package:marieum_app/features/speak/domain/repositories/speak_mode_repository.dart';
import 'package:marieum_app/features/speak/presentation/cubit/speak_mode_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements SpeakModeRepository {}

class _MockSource extends Mock implements SpeakPreferencesDataSource {}

class _MemoryPrefs implements PrefsBackend {
  final values = <String, Object>{};
  @override
  String? readString(String key) => values[key] as String?;
  @override
  bool? readBool(String key) => values[key] as bool?;
  @override
  Future<void> writeString(String key, String value) async =>
      values[key] = value;
  @override
  Future<void> writeBool(String key, {required bool value}) async =>
      values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
}

void main() {
  setUpAll(() => registerFallbackValue(SpeakMode.precise));

  group(SpeakModeCubit, () {
    late _MockRepository repository;
    setUp(() {
      repository = _MockRepository();
      when(() => repository.initialMode).thenReturn(SpeakMode.precise);
    });

    blocTest<SpeakModeCubit, SpeakModeState>(
      'switches immediately and saves the choice',
      build: () {
        when(
          () => repository.save(SpeakMode.live),
        ).thenAnswer((_) async => const Success(null));
        return SpeakModeCubit(repository);
      },
      act: (cubit) => cubit.select(SpeakMode.live),
      expect: () => const [SpeakModeState(SpeakMode.live)],
    );

    blocTest<SpeakModeCubit, SpeakModeState>(
      'keeps the new mode but reports a local save failure',
      build: () {
        when(
          () => repository.save(SpeakMode.live),
        ).thenAnswer((_) async => const FailureResult(StorageFailure()));
        return SpeakModeCubit(repository);
      },
      act: (cubit) => cubit.select(SpeakMode.live),
      expect: () => const [
        SpeakModeState(SpeakMode.live),
        SpeakModeState(SpeakMode.live, failure: StorageFailure()),
      ],
    );
  });

  group(SpeakModeRepositoryImpl, () {
    test('stores locally and mirrors to the server without failing', () async {
      final backend = _MemoryPrefs();
      final source = _MockSource();
      when(
        () => source.mirrorMode(any()),
      ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
      final repository = SpeakModeRepositoryImpl(
        prefs: PrefsStore(backend),
        source: source,
      );
      expect(repository.initialMode, SpeakMode.precise);
      expect(await repository.save(SpeakMode.live), isA<Success<void>>());
      await pumpEventQueue();
      expect(backend.values[PrefsKeys.speakMode], 'live');
      verify(() => source.mirrorMode(SpeakMode.live)).called(1);
      expect(
        SpeakModeRepositoryImpl(
          prefs: PrefsStore(backend),
          source: source,
        ).initialMode,
        SpeakMode.live,
      );
    });
  });
}
