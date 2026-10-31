import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/router/app_router.dart';
import 'package:marieum_app/app/router/auth_router_refresh.dart';
import 'package:marieum_app/core/config/app_config.dart';
import 'package:marieum_app/core/di/voice_dependencies.dart';
import 'package:marieum_app/core/network/api_client.dart';
import 'package:marieum_app/core/network/session_expiry_signal.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/core/storage/secure_token_store.dart';
import 'package:marieum_app/core/storage/sequence_store.dart';
import 'package:marieum_app/core/storage/token_vault.dart';
import 'package:marieum_app/features/auth/data/datasources/auth_data_source.dart';
import 'package:marieum_app/features/auth/data/datasources/mock_auth_data_source.dart';
import 'package:marieum_app/features/auth/data/datasources/remote_auth_data_source.dart';
import 'package:marieum_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/bloc/auth_bloc.dart';
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
    ..registerLazySingleton<AuthDataSource>(
      () => config.useMock
          ? MockAuthDataSource(prefs)
          : RemoteAuthDataSource(dependencies<ApiClient>()),
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
      ),
      dispose: (router) => router.dispose(),
    );
  registerVoiceDependencies(dependencies);
  return dependencies;
}
