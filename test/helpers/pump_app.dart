import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/marieum_app.dart';
import 'package:marieum_app/app/router/app_router.dart';
import 'package:marieum_app/app/router/auth_router_refresh.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/domain/entities/patient_profile.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:marieum_app/features/history/domain/repositories/history_repository.dart';
import 'package:marieum_app/features/history/presentation/cubit/history_cubit.dart';
import 'package:marieum_app/features/insight/domain/entities/insight_summary.dart';
import 'package:marieum_app/features/insight/presentation/cubit/insight_cubit.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/quick_phrase.dart';
import 'package:marieum_app/features/quick_phrase/presentation/bloc/quick_phrase_bloc.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';
import 'package:marieum_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/domain/entities/speak_mode.dart';
import 'package:marieum_app/features/speak/presentation/bloc/utterance_bloc.dart';
import 'package:marieum_app/features/speak/presentation/cubit/playback_cubit.dart';
import 'package:marieum_app/features/speak/presentation/cubit/speak_mode_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockSpeakModeCubit extends MockCubit<SpeakModeState>
    implements SpeakModeCubit {}

class _MockQuickPhraseBloc extends MockBloc<QuickPhraseEvent, QuickPhraseState>
    implements QuickPhraseBloc {}

class _MockPlaybackCubit extends MockCubit<PlaybackState>
    implements PlaybackCubit {}

class _MockUtteranceBloc extends MockBloc<UtteranceEvent, UtteranceState>
    implements UtteranceBloc {}

class _MockHistoryCubit extends MockCubit<HistoryState>
    implements HistoryCubit {}

class _MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _MockHistoryRepository extends Mock implements HistoryRepository {}

class _MockInsightCubit extends MockCubit<InsightState>
    implements InsightCubit {}

const testProfile = PatientProfile(
  id: '1',
  nickname: '김환자',
  onboardingCompleted: true,
  userId: 'demo_a',
);

extension PumpApp on WidgetTester {
  Future<GoRouter> pumpApp({
    String initialLocation = '/speak',
    AuthBloc? authBloc,
    AuthRepository? repository,
    AuthStatus status = const AuthAuthenticated(testProfile),
    bool settle = true,
    SpeakModeCubit? modeCubit,
    SettingsCubit? settingsCubit,
    HistoryCubit Function()? createHistoryCubit,
    InsightCubit Function()? createInsightCubit,
    HistoryRepository? historyRepository,
    String loginUserId = 'demo_a',
    QuickPhraseBloc Function()? createQuickPhraseBloc,
    PlaybackCubit Function(PlaybackRequest)? createPlaybackCubit,
    UtteranceBloc Function()? createUtteranceBloc,
    bool reduceMotion = true,
  }) async {
    // Idle speak-button rings loop forever unless Reduce Motion is on.
    if (reduceMotion) {
      platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(platformDispatcher.clearAccessibilityFeaturesTestValue);
    }
    final bloc = authBloc ?? _MockAuthBloc();
    if (authBloc == null) {
      when(() => bloc.state).thenReturn(AuthState(status));
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
    }
    final authRepository = repository ?? _MockAuthRepository();
    if (repository == null) {
      when(authRepository.restore).thenAnswer((_) async => const Success(null));
    }
    final mode = modeCubit ?? _MockSpeakModeCubit();
    if (modeCubit == null) {
      when(
        () => mode.state,
      ).thenReturn(const SpeakModeState(SpeakMode.precise));
      when(() => mode.stream).thenAnswer((_) => const Stream.empty());
    }
    final settings = settingsCubit ?? _MockSettingsCubit();
    if (settingsCubit == null) {
      when(() => settings.state).thenReturn(const SettingsState(AppSettings()));
      when(() => settings.stream).thenAnswer((_) => const Stream.empty());
    }
    final historyRepositoryValue =
        historyRepository ?? _MockHistoryRepository();
    if (historyRepository == null) {
      when(
        historyRepositoryValue.recent,
      ).thenAnswer((_) async => const Success([]));
    }
    final refresh = AuthRouterRefresh(bloc);
    addTearDown(refresh.dispose);
    final router = createAppRouter(
      initialLocation: initialLocation,
      authBloc: bloc,
      repository: authRepository,
      refresh: refresh,
      readLoginUserId: () => loginUserId,
      createInsightCubit:
          createInsightCubit ??
          () {
            final insight = _MockInsightCubit();
            when(() => insight.state).thenReturn(
              InsightState(
                status: InsightStatus.success,
                summary: InsightSummary.fromEntries(const []),
              ),
            );
            when(() => insight.stream).thenAnswer((_) => const Stream.empty());
            when(insight.load).thenAnswer((_) async {});
            when(insight.close).thenAnswer((_) async {});
            return insight;
          },
      createHistoryCubit:
          createHistoryCubit ??
          () {
            final history = _MockHistoryCubit();
            when(
              () => history.state,
            ).thenReturn(const HistoryState(status: HistoryStatus.success));
            when(() => history.stream).thenAnswer((_) => const Stream.empty());
            when(history.load).thenAnswer((_) async {});
            when(history.close).thenAnswer((_) async {});
            return history;
          },
      createQuickPhraseBloc:
          createQuickPhraseBloc ??
          () {
            final quick = _MockQuickPhraseBloc();
            when(
              () => quick.state,
            ).thenReturn(const QuickPhraseState(phrases: defaultQuickPhrases));
            when(() => quick.stream).thenAnswer((_) => const Stream.empty());
            when(quick.close).thenAnswer((_) async {});
            return quick;
          },
      createUtteranceBloc:
          createUtteranceBloc ??
          () {
            final utterance = _MockUtteranceBloc();
            whenListen(
              utterance,
              const Stream<UtteranceState>.empty(),
              initialState: const UtteranceState(),
            );
            return utterance;
          },
      createPlaybackCubit:
          createPlaybackCubit ??
          (request) {
            final playback = _MockPlaybackCubit();
            when(() => playback.state).thenReturn(
              PlaybackState(text: request.text, status: PlaybackStatus.playing),
            );
            when(() => playback.stream).thenAnswer((_) => const Stream.empty());
            when(playback.start).thenAnswer((_) async {});
            when(playback.close).thenAnswer((_) async {});
            return playback;
          },
    );
    await pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: bloc),
          BlocProvider.value(value: mode),
          BlocProvider.value(value: settings),
        ],
        child: RepositoryProvider<HistoryRepository>.value(
          value: historyRepositoryValue,
          child: MarieumApp(
            router: router,
          ),
        ),
      ),
    );
    if (settle) {
      await pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
    } else {
      await pump();
    }
    return router;
  }
}
