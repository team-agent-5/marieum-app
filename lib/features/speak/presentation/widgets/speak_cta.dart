import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:marieum_app/core/audio/recorder.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/speak/presentation/bloc/utterance_bloc.dart';

/// The single round control on the main screen. One tap starts recording,
/// the next tap (or the 10-second limit) stops it, then it shows analysis.
class SpeakCta extends StatefulWidget {
  const SpeakCta({
    required this.phase,
    required this.elapsed,
    required this.level,
    required this.onPressed,
    required this.onCancel,
    super.key,
  });

  final UtterancePhase phase;
  final Duration elapsed;
  final double level;
  final VoidCallback onPressed;
  final VoidCallback onCancel;

  @override
  State<SpeakCta> createState() => _SpeakCtaState();
}

class _SpeakCtaState extends State<SpeakCta>
    with SingleTickerProviderStateMixin {
  static const _outer = 248.0;
  static const _ring = 216.0;
  static const _button = 184.0;

  late final _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  bool get _recording => widget.phase == UtterancePhase.recording;
  bool get _analyzing => widget.phase == UtterancePhase.analyzing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBreath();
  }

  @override
  void didUpdateWidget(SpeakCta oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBreath();
  }

  void _syncBreath() {
    final animate =
        widget.phase == UtterancePhase.idle &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_breath.isAnimating) {
      unawaited(_breath.repeat());
    } else if (!animate && _breath.isAnimating) {
      _breath
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  String get _clock {
    final seconds = widget.elapsed.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String get _semanticLabel => switch (widget.phase) {
    UtterancePhase.recording =>
      '녹음 중 ${widget.elapsed.inSeconds}초. 말씀이 끝나면 다시 눌러 주세요',
    UtterancePhase.analyzing => '분석하고 있어요',
    _ => '말하기. 한 번 누르면 녹음을 시작해요',
  };

  String get _hint => switch (widget.phase) {
    UtterancePhase.recording => '말씀이 끝나면 다시 눌러 주세요',
    UtterancePhase.analyzing => '분석하고 있어요',
    _ => '한 번 누르고 말씀하세요',
  };

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final remaining =
        1 -
        (widget.elapsed.inMilliseconds / Recorder.maxDuration.inMilliseconds)
            .clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          enabled: !_analyzing,
          label: _semanticLabel,
          excludeSemantics: true,
          onTap: _analyzing ? null : widget.onPressed,
          child: GestureDetector(
            key: const ValueKey('speak_cta'),
            behavior: HitTestBehavior.opaque,
            onTap: _analyzing ? null : widget.onPressed,
            child: SizedBox.square(
              dimension: _outer,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_recording) ...[
                    AnimatedContainer(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 120),
                      width: _ring + (reduceMotion ? 0 : widget.level * 30),
                      height: _ring + (reduceMotion ? 0 : widget.level * 30),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTokens.primary.withValues(
                          alpha: .08 + widget.level * .14,
                        ),
                      ),
                    ),
                    SizedBox.square(
                      dimension: _ring,
                      child: CustomPaint(
                        painter: _CountdownPainter(remaining: remaining),
                      ),
                    ),
                  ] else
                    AnimatedBuilder(
                      animation: _breath,
                      builder: (context, _) => Stack(
                        alignment: Alignment.center,
                        children: [
                          for (final (size, phase) in [
                            (_outer, 0.0),
                            (_ring, .5),
                          ])
                            _BreathRing(
                              size: size,
                              progress: (_breath.value + phase) % 1,
                              animate: _breath.isAnimating,
                            ),
                        ],
                      ),
                    ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _analyzing ? .72 : 1,
                    child: Container(
                      width: _button,
                      height: _button,
                      decoration: BoxDecoration(
                        color: AppTokens.primaryStrong,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTokens.primary, width: 9),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x383564D8),
                            blurRadius: 30,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      child: _content(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ExcludeSemantics(
          child: Text(
            _hint,
            style: const TextStyle(fontSize: 13, color: AppTokens.ink2),
          ),
        ),
        SizedBox(
          height: 44,
          child: _recording
              ? TextButton(
                  key: const ValueKey('speak_cancel'),
                  onPressed: widget.onCancel,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(64, 44),
                    foregroundColor: AppTokens.ink2,
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('취소'),
                )
              : null,
        ),
      ],
    );
  }

  Widget _content() {
    if (_analyzing) {
      return const Center(
        child: SizedBox.square(
          dimension: 44,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            color: AppTokens.surface,
          ),
        ),
      );
    }
    if (_recording) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _clock,
            style: const TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w900,
              color: AppTokens.surface,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.mic_rounded, color: AppTokens.surface, size: 34),
        SizedBox(height: 4),
        Text(
          '말하기',
          style: TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w900,
            color: AppTokens.surface,
          ),
        ),
      ],
    );
  }
}

class _BreathRing extends StatelessWidget {
  const _BreathRing({
    required this.size,
    required this.progress,
    required this.animate,
  });

  final double size;
  final double progress;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final scale = animate ? .9 + progress * .1 : 1.0;
    final alpha = animate ? .3 * (1 - progress) + .08 : .22;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppTokens.primary.withValues(alpha: alpha),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

class _CountdownPainter extends CustomPainter {
  const _CountdownPainter({required this.remaining});

  final double remaining;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas
      ..drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = AppTokens.primarySoft,
      )
      ..drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * remaining,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = AppTokens.primary,
      );
  }

  @override
  bool shouldRepaint(_CountdownPainter oldDelegate) =>
      oldDelegate.remaining != remaining;
}
