import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_top_bar.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/cubit/auth_form_state.dart';
import 'package:marieum_app/features/auth/presentation/cubit/session_action_cubit.dart';
import 'package:marieum_app/features/auth/presentation/widgets/brand_mark.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    required this.repository,
    required this.review,
    super.key,
  });
  final AuthRepository repository;
  final bool review;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => OnboardingCubit(repository),
    child: OnboardingView(review: review),
  );
}

class OnboardingView extends StatelessWidget {
  const OnboardingView({required this.review, super.key});
  final bool review;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AdaptiveTopBar(title: 'Marieum 사용법'),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: BlocBuilder<OnboardingCubit, AuthFormState>(
          builder: (context, state) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: BrandMark(size: 88)),
              const SizedBox(height: 24),
              const Text(
                '내 말을 더 또렷하게',
                textAlign: TextAlign.center,
                style: AppTokens.title,
              ),
              const SizedBox(height: 12),
              const Text(
                '말하기 버튼으로 내 목소리를 전하거나,\n빠른 문장을 골라 들려줄 수 있어요.',
                textAlign: TextAlign.center,
                style: AppTokens.copy,
              ),
              const SizedBox(height: 28),
              if (state.failure != null)
                Text(
                  state.failure!.message,
                  style: const TextStyle(color: AppTokens.danger),
                ),
              FilledButton(
                onPressed: state.status == AuthFormStatus.submitting
                    ? null
                    : () {
                        if (review) {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/speak');
                          }
                        } else {
                          unawaited(context.read<OnboardingCubit>().complete());
                        }
                      },
                child: Text(
                  state.status == AuthFormStatus.submitting
                      ? '저장 중…'
                      : review
                      ? '돌아가기'
                      : '완료',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
