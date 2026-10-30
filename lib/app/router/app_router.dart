import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/navigation/main_navigation_shell.dart';
import 'package:marieum_app/app/router/app_routes.dart';
import 'package:marieum_app/core/ui/placeholder_page.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/domain/entities/speak_mode.dart';

/// T1 route scaffold. Repository-driven authentication guards belong to T3.
GoRouter createAppRouter({String initialLocation = AppRoutes.speak}) {
  final rootKey = GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
    onException: (_, _, router) => router.go(AppRoutes.speak),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainNavigationShell(shell: shell),
        branches: [
          for (final path in [
            AppRoutes.speak,
            AppRoutes.history,
            AppRoutes.settings,
          ])
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: path,
                  builder: (context, state) => const SizedBox.expand(),
                ),
              ],
            ),
        ],
      ),
      GoRoute(
        path: AppRoutes.utterance,
        parentNavigatorKey: rootKey,
        redirect: (context, state) =>
            state.extra is SpeakMode ? null : AppRoutes.speak,
        builder: (context, state) => const PlaceholderPage(title: '내 목소리로 말하기'),
      ),
      GoRoute(
        path: AppRoutes.playback,
        parentNavigatorKey: rootKey,
        redirect: (context, state) =>
            state.extra is PlaybackRequest ? null : AppRoutes.speak,
        builder: (context, state) => const PlaceholderPage(title: '음성 재생'),
      ),
      for (final entry in const {
        AppRoutes.splash: 'Marieum',
        AppRoutes.login: '로그인',
        AppRoutes.signup: '회원가입',
        AppRoutes.onboarding: 'Marieum 사용법',
        AppRoutes.quickPhrases: '빠른 문장 관리',
        AppRoutes.insight: '개인화 현황',
        AppRoutes.account: '계정 관리',
        AppRoutes.privacy: '개인정보·데이터',
      }.entries)
        GoRoute(
          path: entry.key,
          parentNavigatorKey: rootKey,
          builder: (context, state) => PlaceholderPage(title: entry.value),
        ),
    ],
  );
}
