import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/core/theme/app_theme.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/key_text.dart';
import 'package:marieum_app/features/settings/presentation/cubit/settings_cubit.dart';

class MarieumApp extends StatelessWidget {
  const MarieumApp({required this.router, super.key});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Marieum',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: router,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final boundedMedia = media.copyWith(
          textScaler: media.textScaler.clamp(
            maxScaleFactor: AppTokens.maxTextScale,
          ),
        );
        return MediaQuery(
          data: boundedMedia,
          child: BlocSelector<SettingsCubit, SettingsState, bool>(
            selector: (state) => state.settings.largeText,
            builder: (context, large) => LargeTextScope(
              enabled: large,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}
