import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/router/app_router.dart';
import 'package:marieum_app/core/config/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads preferences before any future settings or mode cubit is constructed.
Future<GetIt> configureDependencies({
  AppConfig config = const AppConfig.fromEnvironment(),
}) async {
  final preferences = await SharedPreferences.getInstance();
  final dependencies = GetIt.asNewInstance()
    ..registerSingleton<AppConfig>(config)
    ..registerSingleton<SharedPreferences>(preferences)
    ..registerLazySingleton<GoRouter>(
      createAppRouter,
      dispose: (router) => router.dispose(),
    );
  return dependencies;
}
