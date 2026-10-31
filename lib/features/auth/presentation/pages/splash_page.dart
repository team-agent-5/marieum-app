import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/cubit/auth_form_state.dart';
import 'package:marieum_app/features/auth/presentation/cubit/session_action_cubit.dart';
import 'package:marieum_app/features/auth/presentation/widgets/brand_mark.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({required this.repository, super.key});
  final AuthRepository repository;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = RestoreCubit(repository);
      unawaited(cubit.restore());
      return cubit;
    },
    child: const SplashView(),
  );
}

class SplashView extends StatelessWidget {
  const SplashView({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -.24),
          radius: .9,
          colors: [
            AppTokens.surface,
            AppTokens.surfaceBlue,
            AppTokens.primarySoft,
          ],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(34),
            child: BlocBuilder<RestoreCubit, AuthFormState>(
              builder: (context, state) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const BrandMark(size: 104),
                  const SizedBox(height: 15),
                  const Text(
                    'Marieum',
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      color: AppTokens.ink,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    '당신의 말을\n더 또렷하게 이어드려요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.5,
                      color: AppTokens.ink2,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (state.status == AuthFormStatus.failure) ...[
                    Text(
                      state.failure!.message,
                      textAlign: TextAlign.center,
                      style: AppTokens.copy,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => context.read<RestoreCubit>().restore(),
                      child: const Text('다시 시도'),
                    ),
                  ] else
                    SizedBox(
                      width: 112,
                      child: LinearProgressIndicator(
                        semanticsLabel: '세션 확인 중',
                        value: MediaQuery.disableAnimationsOf(context)
                            ? .45
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
