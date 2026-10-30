import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/core/config/app_config.dart';
import 'package:marieum_app/core/theme/app_theme.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/safety_banner.dart';

class MarieumApp extends StatelessWidget {
  const MarieumApp({required this.config, required this.router, super.key});

  final AppConfig config;
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
          child: Column(
            children: [
              if (config.showSafetyBanner) const SafetyBanner(),
              Expanded(
                child: MediaQuery(
                  data: boundedMedia.removePadding(
                    removeTop: config.showSafetyBanner,
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
