import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/router/app_router.dart';
import 'package:marieum_app/core/config/app_config.dart';
import 'package:marieum_app/core/di/voice_dependencies.dart';
import 'package:marieum_app/core/network/api_client.dart';
import 'package:marieum_app/core/network/session_expiry_signal.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/core/storage/secure_token_store.dart';
import 'package:marieum_app/core/storage/sequence_store.dart';
import 'package:marieum_app/core/storage/token_vault.dart';
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
    ..registerLazySingleton<GoRouter>(
      createAppRouter,
      dispose: (router) => router.dispose(),
    );
  registerVoiceDependencies(dependencies);
  return dependencies;
}
