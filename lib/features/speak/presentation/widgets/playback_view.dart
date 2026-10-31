import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/speak/presentation/cubit/playback_cubit.dart';

class PlaybackView extends StatelessWidget {
  const PlaybackView({super.key});
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<PlaybackCubit, PlaybackState>(
    builder: (context, state) {
      final done = state.status == PlaybackStatus.completed;
      final failed = state.status == PlaybackStatus.failed;
      return Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: SizedBox(
                height: constraints.maxHeight < 480
                    ? 480
                    : constraints.maxHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                state.text,
                                textAlign: TextAlign.center,
                                style: AppTokens.phrase.copyWith(
                                  color: done ? AppTokens.ink2 : AppTokens.ink,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _PlaybackBadge(done: done, failed: failed),
                              const SizedBox(height: 24),
                              if (failed)
                                Text(
                                  state.failure!.message,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: AppTokens.danger,
                                  ),
                                )
                              else if (done) ...[
                                const Text(
                                  '잠시 뒤 이전 화면으로 돌아가요',
                                  style: AppTokens.copy,
                                ),
                                const SizedBox(height: 20),
                                const _ReturnProgress(),
                              ] else
                                const _VoiceWave(),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          onPressed: () =>
                              unawaited(context.read<PlaybackCubit>().stop()),
                          child: Text(done || failed ? '지금 돌아가기' : '재생 중지'),
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
    },
  );
}

class _PlaybackBadge extends StatelessWidget {
  const _PlaybackBadge({required this.done, required this.failed});
  final bool done;
  final bool failed;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    decoration: BoxDecoration(
      color: done
          ? AppTokens.success
          : failed
          ? AppTokens.dangerSoft
          : AppTokens.primarySoft,
      borderRadius: BorderRadius.circular(32),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done
              ? Icons.check_rounded
              : failed
              ? Icons.volume_off_rounded
              : Icons.volume_up_rounded,
          color: done
              ? AppTokens.surface
              : failed
              ? AppTokens.danger
              : AppTokens.onTonal,
        ),
        const SizedBox(width: 10),
        Text(
          done
              ? '전달됐어요'
              : failed
              ? '소리를 재생하지 못했어요'
              : '말하고 있어요',
          style: TextStyle(
            fontSize: done ? 21 : 17,
            fontWeight: FontWeight.w800,
            color: done
                ? AppTokens.surface
                : failed
                ? AppTokens.danger
                : AppTokens.onTonal,
          ),
        ),
      ],
    ),
  );
}

class _ReturnProgress extends StatelessWidget {
  const _ReturnProgress();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 140,
    child: TweenAnimationBuilder<double>(
      key: const ValueKey('playback_return_progress'),
      tween: Tween(begin: 0, end: 1),
      duration: PlaybackCubit.returnDelay,
      builder: (context, value, _) => LinearProgressIndicator(value: value),
    ),
  );
}

class _VoiceWave extends StatefulWidget {
  const _VoiceWave();
  @override
  State<_VoiceWave> createState() => _VoiceWaveState();
}

class _VoiceWaveState extends State<_VoiceWave>
    with SingleTickerProviderStateMixin {
  static const _heights = [
    14.0,
    24.0,
    36.0,
    44.0,
    30.0,
    20.0,
    38.0,
    26.0,
    14.0,
  ];

  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 44,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _heights.length; i++)
              _bar(_heights[i], _scale(i)),
          ],
        ),
      ),
    ),
  );

  double _scale(int index) {
    if (!_controller.isAnimating) return 1;
    final phase = (_controller.value - (index - 4).abs() * .1) % 1;
    return .45 + .55 * (0.5 + 0.5 * math.cos(phase * 2 * math.pi));
  }

  Widget _bar(double height, double scale) => Container(
    width: 5,
    height: height * scale,
    margin: const EdgeInsets.symmetric(horizontal: 3),
    decoration: BoxDecoration(
      color: AppTokens.primary.withValues(alpha: .5 + .5 * scale),
      borderRadius: BorderRadius.circular(3),
    ),
  );
}
