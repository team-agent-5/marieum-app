import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/navigation/main_navigation_shell.dart';
import 'package:marieum_app/app/providers/authenticated_quick_phrase_scope.dart';
import 'package:marieum_app/app/router/app_routes.dart';
import 'package:marieum_app/app/router/auth_router_refresh.dart';
import 'package:marieum_app/core/ui/placeholder_page.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:marieum_app/features/auth/presentation/pages/login_page.dart';
import 'package:marieum_app/features/auth/presentation/pages/onboarding_page.dart';
import 'package:marieum_app/features/auth/presentation/pages/signup_page.dart';
import 'package:marieum_app/features/auth/presentation/pages/splash_page.dart';
import 'package:marieum_app/features/quick_phrase/presentation/bloc/quick_phrase_bloc.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/presentation/bloc/utterance_bloc.dart';
import 'package:marieum_app/features/speak/presentation/cubit/playback_cubit.dart';
import 'package:marieum_app/features/speak/presentation/pages/playback_page.dart';
import 'package:marieum_app/features/speak/presentation/pages/speak_page.dart';

GoRouter createAppRouter({
  required AuthBloc authBloc,
  required AuthRepository repository,
  required AuthRouterRefresh refresh,
  required QuickPhraseBloc Function() createQuickPhraseBloc,
  required PlaybackCubit Function(PlaybackRequest) createPlaybackCubit,
  required UtteranceBloc Function() createUtteranceBloc,
  String initialLocation = AppRoutes.splash,
}) {
  final rootKey = GlobalKey<NavigatorState>();
  final authenticatedKey = GlobalKey<NavigatorState>();
  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
    refreshListenable: refresh,
    redirect: (context, state) {
      final path = state.uri.path;
      final review = state.uri.queryParameters['review'] == '1';
      return switch (authBloc.state.status) {
        AuthUnknown() => path == AppRoutes.splash ? null : AppRoutes.splash,
        AuthUnauthenticated() =>
          [AppRoutes.login, AppRoutes.signup].contains(path)
              ? null
              : AppRoutes.login,
        AuthAuthenticated(:final profile) when !profile.onboardingCompleted =>
          path == AppRoutes.onboarding && !review ? null : AppRoutes.onboarding,
        AuthAuthenticated() =>
          [
                    AppRoutes.splash,
                    AppRoutes.login,
                    AppRoutes.signup,
                  ].contains(path) ||
                  (path == AppRoutes.onboarding && !review)
              ? AppRoutes.speak
              : null,
      };
    },
    onException: (_, _, router) => router.go(AppRoutes.speak),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, _) => SplashPage(repository: repository),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => LoginPage(repository: repository),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (_, _) => SignupPage(repository: repository),
      ),
      ShellRoute(
        navigatorKey: authenticatedKey,
        builder: (context, state, child) => AuthenticatedQuickPhraseScope(
          createBloc: createQuickPhraseBloc,
          child: child,
        ),
        routes: [
          GoRoute(
            path: AppRoutes.onboarding,
            builder: (_, state) => OnboardingPage(
              repository: repository,
              review: state.uri.queryParameters['review'] == '1',
            ),
          ),
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => BlocProvider(
              create: (_) => createUtteranceBloc(),
              child: MainNavigationShell(shell: shell),
            ),
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
                      builder: (context, state) => path == AppRoutes.speak
                          ? const SpeakPage()
                          : const SizedBox.expand(),
                    ),
                  ],
                ),
            ],
          ),
          GoRoute(
            path: AppRoutes.playback,
            parentNavigatorKey: authenticatedKey,
            redirect: (context, state) =>
                state.extra is PlaybackRequest ? null : AppRoutes.speak,
            builder: (context, state) => PlaybackPage(
              request: state.extra! as PlaybackRequest,
              createCubit: createPlaybackCubit,
            ),
          ),
          for (final entry in const {
            AppRoutes.quickPhrases: '빠른 문장 관리',
            AppRoutes.insight: '개인화 현황',
            AppRoutes.account: '계정 관리',
            AppRoutes.privacy: '개인정보·데이터',
          }.entries)
            GoRoute(
              path: entry.key,
              parentNavigatorKey: authenticatedKey,
              builder: (context, state) => PlaceholderPage(title: entry.value),
            ),
        ],
      ),
    ],
  );
}
