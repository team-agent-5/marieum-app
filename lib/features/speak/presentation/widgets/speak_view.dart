import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/navigation/push_drawer.dart';
import 'package:marieum_app/app/router/app_routes.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_segmented_control.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/quick_phrase.dart';
import 'package:marieum_app/features/quick_phrase/presentation/bloc/quick_phrase_bloc.dart';
import 'package:marieum_app/features/quick_phrase/presentation/widgets/play_quick_phrase.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/domain/entities/speak_mode.dart';
import 'package:marieum_app/features/speak/presentation/bloc/utterance_bloc.dart';
import 'package:marieum_app/features/speak/presentation/cubit/speak_mode_cubit.dart';
import 'package:marieum_app/features/speak/presentation/widgets/quick_phrase_carousel.dart';
import 'package:marieum_app/features/speak/presentation/widgets/speak_cta.dart';
import 'package:marieum_app/features/speak/presentation/widgets/utterance_sheet.dart';

class SpeakView extends StatefulWidget {
  const SpeakView({super.key});

  @override
  State<SpeakView> createState() => _SpeakViewState();
}

class _SpeakViewState extends State<SpeakView> {
  bool _sheetOpen = false;
  BuildContext? _sheetContext;

  void _onUtterance(BuildContext context, UtteranceState state) {
    if (state.phase.usesSheet && !_sheetOpen) {
      unawaited(_openSheet(context));
    } else if (!state.phase.usesSheet && _sheetOpen) {
      final sheet = _sheetContext;
      if (sheet != null && sheet.mounted) Navigator.of(sheet).pop();
    }
  }

  Future<void> _openSheet(BuildContext context) async {
    final utterance = context.read<UtteranceBloc>();
    final quickPhrases = context.read<QuickPhraseBloc>();
    _sheetOpen = true;
    final picked = await showModalBottomSheet<QuickPhrase>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppTokens.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        _sheetContext = sheetContext;
        return MultiBlocProvider(
          providers: [
            BlocProvider.value(value: utterance),
            BlocProvider.value(value: quickPhrases),
          ],
          child: const UtteranceSheet(),
        );
      },
    );
    _sheetOpen = false;
    _sheetContext = null;
    if (utterance.state.phase.usesSheet) {
      utterance.add(const UtteranceSheetDismissed());
    }
    if (picked != null && context.mounted) playQuickPhrase(context, picked);
  }

  @override
  Widget build(BuildContext context) => MultiBlocListener(
    listeners: [
      BlocListener<UtteranceBloc, UtteranceState>(
        listenWhen: (previous, current) => previous.phase != current.phase,
        listener: _onUtterance,
      ),
      BlocListener<UtteranceBloc, UtteranceState>(
        listenWhen: (previous, current) =>
            previous.playbackId != current.playbackId &&
            current.spokenText != null,
        listener: (context, state) => unawaited(
          context.push<void>(
            AppRoutes.playback,
            extra: PlaybackRequest(
              text: state.spokenText!,
              origin: PlaybackOrigin.utterance,
              suggestions: state.suggestions,
              transcription: state.transcription,
            ),
          ),
        ),
      ),
    ],
    child: BlocBuilder<SpeakModeCubit, SpeakModeState>(
      builder: (context, mode) => BlocBuilder<UtteranceBloc, UtteranceState>(
        buildWhen: (previous, current) =>
            previous.phase != current.phase ||
            previous.elapsed != current.elapsed ||
            previous.level != current.level,
        builder: (context, utterance) {
          final locked = utterance.phase.locksScreen;
          return SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: locked ? const NeverScrollableScrollPhysics() : null,
                child: SizedBox(
                  height: math.max(
                    664 +
                        (MediaQuery.textScalerOf(context).scale(16) / 16 - 1) *
                            260,
                    constraints.maxHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                    child: Column(
                      children: [
                        _Locked(
                          locked: locked,
                          child: Column(
                            children: [
                              _Greeting(mode: mode.mode),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: AdaptiveSegmentedControl<SpeakMode>(
                                  value: mode.mode,
                                  selectedBackground:
                                      mode.mode == SpeakMode.live
                                      ? AppTokens.warningSoft
                                      : AppTokens.primarySoft,
                                  onChanged: (next) => unawaited(
                                    context.read<SpeakModeCubit>().select(next),
                                  ),
                                  children: {
                                    for (final option in SpeakMode.values)
                                      option: _ModeLabel(
                                        mode: option,
                                        selected: mode.mode == option,
                                      ),
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: SpeakCta(
                              phase: utterance.phase,
                              elapsed: utterance.elapsed,
                              level: utterance.level,
                              hold: mode.mode == SpeakMode.precise,
                              onPressed: () => mode.mode == SpeakMode.live
                                  ? unawaited(
                                      context.push<void>(AppRoutes.live),
                                    )
                                  : context.read<UtteranceBloc>().add(
                                      UtteranceButtonPressed(mode.mode),
                                    ),
                              onHoldStart: () => context
                                  .read<UtteranceBloc>()
                                  .add(UtteranceHoldStarted(mode.mode)),
                              onHoldEnd: () => context
                                  .read<UtteranceBloc>()
                                  .add(const UtteranceHoldEnded()),
                            ),
                          ),
                        ),
                        _Locked(
                          locked: locked,
                          child: QuickPhraseCarousel(enabled: !locked),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// Blocks touches and hides the controls from assistive tech while recording.
class _Locked extends StatelessWidget {
  const _Locked({required this.locked, required this.child});
  final bool locked;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: locked,
    child: ExcludeSemantics(
      excluding: locked,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: locked ? .45 : 1,
        child: child,
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
          onPressed: () => PushDrawerScope.of(context).open(),
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
                      : AppTokens.onTonal)
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
