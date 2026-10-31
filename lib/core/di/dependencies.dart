import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/router/app_router.dart';
import 'package:marieum_app/app/router/auth_router_refresh.dart';
import 'package:marieum_app/core/audio/mic_stream.dart';
import 'package:marieum_app/core/audio/recorder.dart';
import 'package:marieum_app/core/config/app_config.dart';
import 'package:marieum_app/core/di/voice_dependencies.dart';
import 'package:marieum_app/core/haptics/haptics.dart';
import 'package:marieum_app/core/network/api_client.dart';
import 'package:marieum_app/core/network/session_expiry_signal.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/core/storage/secure_token_store.dart';
import 'package:marieum_app/core/storage/sequence_store.dart';
import 'package:marieum_app/core/storage/token_vault.dart';
import 'package:marieum_app/core/tts/cloud_tts_port.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/core/tts/tts_service.dart';
import 'package:marieum_app/features/auth/data/datasources/auth_data_source.dart';
import 'package:marieum_app/features/auth/data/datasources/remote_auth_data_source.dart';
import 'package:marieum_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:marieum_app/features/history/data/datasources/history_data_source.dart';
import 'package:marieum_app/features/history/data/datasources/remote_history_data_source.dart';
import 'package:marieum_app/features/history/data/repositories/history_repository_impl.dart';
import 'package:marieum_app/features/history/domain/repositories/history_repository.dart';
import 'package:marieum_app/features/history/presentation/cubit/history_cubit.dart';
import 'package:marieum_app/features/insight/presentation/cubit/insight_cubit.dart';
import 'package:marieum_app/features/quick_phrase/data/datasources/preset_data_source.dart';
import 'package:marieum_app/features/quick_phrase/data/datasources/quick_phrase_local_store.dart';
import 'package:marieum_app/features/quick_phrase/data/repositories/quick_phrase_repository_impl.dart';
import 'package:marieum_app/features/quick_phrase/domain/repositories/quick_phrase_repository.dart';
import 'package:marieum_app/features/quick_phrase/presentation/bloc/quick_phrase_bloc.dart';
import 'package:marieum_app/features/settings/data/datasources/remote_settings_mirror.dart';
import 'package:marieum_app/features/settings/data/datasources/settings_mirror.dart';
import 'package:marieum_app/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:marieum_app/features/settings/domain/repositories/settings_repository.dart';
import 'package:marieum_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:marieum_app/features/speak/data/datasources/phrase_stream_source.dart';
import 'package:marieum_app/features/speak/data/datasources/selection_log_queue.dart';
import 'package:marieum_app/features/speak/data/datasources/speak_preferences_data_source.dart';
import 'package:marieum_app/features/speak/data/datasources/utterance_data_source.dart';
import 'package:marieum_app/features/speak/data/repositories/speak_mode_repository_impl.dart';
import 'package:marieum_app/features/speak/data/repositories/utterance_repository_impl.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/domain/repositories/live_stream.dart';
import 'package:marieum_app/features/speak/domain/repositories/speak_mode_repository.dart';
import 'package:marieum_app/features/speak/domain/repositories/utterance_repository.dart';
import 'package:marieum_app/features/speak/presentation/bloc/utterance_bloc.dart';
import 'package:marieum_app/features/speak/presentation/cubit/live_session_cubit.dart';
import 'package:marieum_app/features/speak/presentation/cubit/playback_cubit.dart';
import 'package:marieum_app/features/speak/presentation/cubit/speak_mode_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads preferences before any future settings or mode cubit is constructed.
Future<GetIt> configureDependencies({
  AppConfig config = const AppConfig.fromEnvironment(),
  TokenVault? tokenVault,
}) async {
  final preferences = await SharedPreferences.getInstance();
  final prefs = PrefsStore(SharedPrefsBackend(preferences));
  final tokens = SecureTokenStore(
    vault: tokenVault ?? PlatformTokenVault(),
    prefs: prefs,
  );
  await tokens.initialize();
  final dependencies = GetIt.asNewInstance();
  dependencies
    ..registerSingleton<AppConfig>(config)
    ..registerSingleton<SharedPreferences>(preferences)
    ..registerSingleton<PrefsStore>(prefs)
    ..registerSingleton<SecureTokenStore>(tokens)
    ..registerSingleton<SequenceStore>(SequenceStore(prefs))
    ..registerLazySingleton<SessionExpirySignal>(
      SessionExpirySignal.new,
      dispose: (signal) => signal.dispose(),
    )
    ..registerLazySingleton<Dio>(
      () => createApiDio(
        config: config,
        tokens: tokens,
        expiry: dependencies<SessionExpirySignal>(),
      ),
      dispose: (dio) => dio.close(force: true),
    )
    ..registerLazySingleton<ApiClient>(() => ApiClient(dependencies<Dio>()))
    ..registerLazySingleton<SpeakPreferencesDataSource>(
      () => RemoteSpeakPreferencesDataSource(dependencies<ApiClient>()),
    )
    ..registerLazySingleton<SpeakModeRepository>(
      () => SpeakModeRepositoryImpl(
        prefs: prefs,
        source: dependencies<SpeakPreferencesDataSource>(),
      ),
    )
    ..registerSingleton<SpeakModeCubit>(
      SpeakModeCubit(dependencies<SpeakModeRepository>()),
      dispose: (cubit) => cubit.close(),
    )
    ..registerLazySingleton<PresetDataSource>(
      () => RemotePresetDataSource(dependencies<ApiClient>()),
    )
    ..registerLazySingleton<QuickPhraseRepository>(
      () => QuickPhraseRepositoryImpl(
        store: QuickPhraseLocalStore(prefs),
        source: dependencies<PresetDataSource>(),
        sequence: dependencies<SequenceStore>(),
      ),
    )
    ..registerFactory<QuickPhraseBloc>(
      () => QuickPhraseBloc(dependencies<QuickPhraseRepository>()),
    )
    ..registerLazySingleton<AuthDataSource>(
      () => RemoteAuthDataSource(dependencies<ApiClient>()),
    )
    ..registerLazySingleton<AuthRepository>(
      () => AuthRepositoryImpl(
        source: dependencies<AuthDataSource>(),
        tokens: tokens,
        prefs: prefs,
        sequence: dependencies<SequenceStore>(),
        expiry: dependencies<SessionExpirySignal>(),
      ),
      dispose: (repository) => repository.dispose(),
    )
    ..registerLazySingleton<AuthBloc>(
      () =>
          AuthBloc(dependencies<AuthRepository>())
            ..add(const AuthSubscriptionRequested()),
      dispose: (bloc) => bloc.close(),
    )
    ..registerLazySingleton<AuthRouterRefresh>(
      () => AuthRouterRefresh(dependencies<AuthBloc>()),
      dispose: (refresh) => refresh.dispose(),
    )
    ..registerLazySingleton<GoRouter>(
      () => createAppRouter(
        authBloc: dependencies<AuthBloc>(),
        repository: dependencies<AuthRepository>(),
        refresh: dependencies<AuthRouterRefresh>(),
        createQuickPhraseBloc: dependencies.call<QuickPhraseBloc>,
        createHistoryCubit: dependencies.call<HistoryCubit>,
        createInsightCubit: dependencies.call<InsightCubit>,
        readLoginUserId: () => prefs.readString(PrefsKeys.loginUserId) ?? '',
        createPlaybackCubit: (request) => PlaybackCubit(
          request: request,
          tts: request.origin == PlaybackOrigin.utterance
              ? dependencies<TtsService>()
              : dependencies<TtsPort>(),
          repository: dependencies<UtteranceRepository>(),
          haptics: dependencies<VoiceHaptics>(),
        ),
        createUtteranceBloc: dependencies.call<UtteranceBloc>,
        createLiveSessionCubit: dependencies.call<LiveSessionCubit>,
      ),
      dispose: (router) => router.dispose(),
    )
    ..registerLazySingleton<UtteranceDataSource>(
      () => RemoteUtteranceDataSource(dependencies<ApiClient>()),
    )
    ..registerLazySingleton<UtteranceRepository>(
      () => UtteranceRepositoryImpl(
        source: dependencies<UtteranceDataSource>(),
        sequence: dependencies<SequenceStore>(),
        queue: SelectionLogQueue(
          prefs: prefs,
          sequence: dependencies<SequenceStore>(),
          send: (body) => dependencies<UtteranceDataSource>().selection(body),
        ),
      ),
    )
    ..registerLazySingleton<LiveStream>(
      () => PhraseStreamSource(
        endpoint: PhraseStreamSource.endpointFor(
          config.wsUrl.isEmpty ? config.baseUrl : config.wsUrl,
        ),
        tokens: dependencies<SecureTokenStore>(),
        expiry: dependencies<SessionExpirySignal>(),
      ),
    )
    ..registerFactory<LiveSessionCubit>(
      () => LiveSessionCubit(
        mic: dependencies<MicStream>(),
        stream: dependencies<LiveStream>(),
        repository: dependencies<UtteranceRepository>(),
        tts: dependencies<PlaybackTtsPort>(),
      ),
    )
    ..registerFactory<UtteranceBloc>(
      () => UtteranceBloc(
        repository: dependencies<UtteranceRepository>(),
        createRecorder: dependencies.call<Recorder>,
        haptics: dependencies<VoiceHaptics>(),
      ),
    );
  registerVoiceDependencies(
    dependencies,
    cloudApiKey: config.copaApiKey,
    warmTexts: () => [
      for (final phrase in dependencies<QuickPhraseRepository>().load())
        phrase.text,
    ],
  );
  dependencies
    ..registerLazySingleton<HistoryDataSource>(
      () => RemoteHistoryDataSource(dependencies<ApiClient>()),
    )
    ..registerLazySingleton<HistoryRepository>(
      () => HistoryRepositoryImpl(dependencies<HistoryDataSource>()),
    )
    ..registerFactory<InsightCubit>(
      () => InsightCubit(dependencies<HistoryRepository>()),
    )
    ..registerFactory<HistoryCubit>(
      () => HistoryCubit(dependencies<HistoryRepository>()),
    )
    ..registerLazySingleton<SettingsMirror>(
      () => RemoteSettingsMirror(dependencies<ApiClient>()),
    )
    ..registerSingleton<SettingsRepository>(
      SettingsRepositoryImpl(
        prefs: prefs,
        mirror: dependencies<SettingsMirror>(),
        applyVoice: (settings) {
          dependencies<TtsService>()
            ..rate = settings.rate
            ..volume = settings.volume;
          dependencies<CloudTtsPort>()
            ..rate = settings.rate
            ..volume = settings.volume
            ..voice = settings.cloudVoice;
          unawaited(dependencies<TtsService>().selectVoice(settings.voiceId));
        },
      ),
    )
    ..registerSingleton<SettingsCubit>(
      SettingsCubit(
        dependencies<SettingsRepository>(),
        voices: dependencies<TtsService>(),
        cloudVoiceAvailable: dependencies<CloudTtsPort>().enabled,
      ),
      dispose: (cubit) => cubit.close(),
    );
  return dependencies;
}
