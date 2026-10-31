import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_top_bar.dart';
import 'package:marieum_app/core/ui/key_text.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/cubit/auth_form_state.dart';
import 'package:marieum_app/features/auth/presentation/cubit/session_action_cubit.dart';

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

class OnboardingView extends StatefulWidget {
  const OnboardingView({required this.review, super.key});
  final bool review;
  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  int _step = 0;
  final _pages = PageController();

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(step);
    } else {
      unawaited(
        _pages.animateToPage(
          step,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  static const _copy = [
    ('말하기 버튼을 한 번 눌러 녹음하고, 다시 눌러 끝내요', '말을 끝내면 비슷한 문장을 찾아드려요.'),
    ('비슷한 말 3개 중 하나를 골라요', '환자 본인의 이력과 시간대를 반영하고, 추천 이유도 함께 보여드려요.'),
    ('또렷한 소리로 자동 재생돼요', '선택한 문장을 큰 글자로 보여주고 옆 사람에게 바로 들려드려요.'),
  ];
  void _closeReview() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/speak');
    }
  }

  void _finish() {
    if (widget.review) {
      _closeReview();
    } else {
      unawaited(context.read<OnboardingCubit>().complete());
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<OnboardingCubit, AuthFormState>(
    builder: (context, state) {
      final busy = state.status == AuthFormStatus.submitting;
      return Scaffold(
        appBar: AdaptiveTopBar(
          title: 'Marieum 사용법',
          leading: _step > 0 || widget.review
              ? IconButton(
                  tooltip: '뒤로',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: busy
                      ? null
                      : () {
                          if (_step > 0) {
                            _goTo(_step - 1);
                          } else {
                            _closeReview();
                          }
                        },
                )
              : null,
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  key: const ValueKey('onboarding_pages'),
                  controller: _pages,
                  itemCount: _copy.length,
                  physics: busy ? const NeverScrollableScrollPhysics() : null,
                  onPageChanged: (page) => setState(() => _step = page),
                  itemBuilder: (context, page) => SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        _OnboardingArt(step: page),
                        const SizedBox(height: 22),
                        KeyText(
                          _copy[page].$1,
                          textAlign: TextAlign.center,
                          style: AppTokens.title,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _copy[page].$2,
                          textAlign: TextAlign.center,
                          style: AppTokens.copy,
                        ),
                        if (state.failure != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(
                              state.failure!.message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTokens.danger),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Container(
                            width: i == _step ? 24 : 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 3.5,
                            ),
                            decoration: BoxDecoration(
                              color: i == _step
                                  ? AppTokens.primaryStrong
                                  : AppTokens.lineStrong,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () {
                              if (_step < 2) {
                                _goTo(_step + 1);
                              } else {
                                _finish();
                              }
                            },
                      child: KeyText(
                        busy
                            ? '저장 중…'
                            : _step < 2
                            ? '다음'
                            : widget.review
                            ? '돌아가기'
                            : '시작하기',
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : _finish,
                      child: Text(widget.review ? '닫기' : '건너뛰기'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _OnboardingArt extends StatelessWidget {
  const _OnboardingArt({required this.step});
  final int step;
  @override
  Widget build(BuildContext context) => Container(
    height: 248,
    width: double.infinity,
    decoration: BoxDecoration(
      color: AppTokens.surfaceBlue,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppTokens.line),
    ),
    child: Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: ExcludeSemantics(
              child: SvgPicture.asset(
                'assets/onboarding/step_${step + 1}.svg',
                height: 210,
              ),
            ),
          ),
        ),
        Positioned(
          top: 14,
          right: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${step + 1} / 3',
              style: const TextStyle(
                color: AppTokens.primaryStrong,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
