import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_segmented_control.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:marieum_app/features/speak/domain/entities/speak_mode.dart';
import 'package:marieum_app/features/speak/presentation/cubit/speak_mode_cubit.dart';
import 'package:marieum_app/features/speak/presentation/widgets/quick_phrase_carousel.dart';
import 'package:marieum_app/features/speak/presentation/widgets/speak_cta.dart';

class SpeakView extends StatelessWidget {
  const SpeakView({super.key});
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<SpeakModeCubit, SpeakModeState>(
    builder: (context, state) => LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: SizedBox(
          height: math.max(
            620 + (MediaQuery.textScalerOf(context).scale(16) / 16 - 1) * 260,
            constraints.maxHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: Column(
              children: [
                _Greeting(mode: state.mode),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: AdaptiveSegmentedControl<SpeakMode>(
                    value: state.mode,
                    selectedBackground: state.mode == SpeakMode.live
                        ? AppTokens.warningSoft
                        : null,
                    onChanged: (mode) =>
                        unawaited(context.read<SpeakModeCubit>().select(mode)),
                    children: {
                      for (final mode in SpeakMode.values)
                        mode: _ModeLabel(
                          mode: mode,
                          selected: state.mode == mode,
                        ),
                    },
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SpeakCta(
                      onLongPress: () {
                        final mode = context.read<SpeakModeCubit>().state.mode;
                        unawaited(
                          context.push<void>('/speak/utterance', extra: mode),
                        );
                      },
                    ),
                  ),
                ),
                const QuickPhraseCarousel(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.mode});
  final SpeakMode mode;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTokens.surface,
          border: Border.all(color: AppTokens.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: IconButton(
          tooltip: '메뉴 열기',
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: BlocSelector<AuthBloc, AuthState, String>(
                    selector: (state) => switch (state.status) {
                      AuthAuthenticated(:final profile) => profile.nickname,
                      _ => '',
                    },
                    builder: (context, nickname) => Text(
                      '$nickname님',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTokens.ink,
                      ),
                    ),
                  ),
                ),
                if (mode == SpeakMode.live)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTokens.warningSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '실시간',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTokens.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            Text(
              mode == SpeakMode.live ? '말이 끝나면 바로 전달해요' : '오늘도 편하게 말씀해 보세요',
              style: const TextStyle(fontSize: 13, color: AppTokens.ink2),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ModeLabel extends StatelessWidget {
  const _ModeLabel({required this.mode, required this.selected});
  final SpeakMode mode;
  final bool selected;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      children: [
        Text(
          mode == SpeakMode.live ? '실시간 모드' : '정확도 모드',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: selected
                ? (mode == SpeakMode.live
                      ? AppTokens.warning
                      : AppTokens.primaryStrong)
                : AppTokens.ink2,
          ),
        ),
        Text(
          mode == SpeakMode.live ? '말이 끝나면 바로 재생' : '후보를 보고 선택',
          style: const TextStyle(fontSize: 10.5, color: AppTokens.ink2),
        ),
      ],
    ),
  );
}
