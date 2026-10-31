import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:marieum_app/core/theme/tokens.dart';

/// Nine pulsing bars. [level] (0..1) scales the pulse to the input loudness;
/// with reduce motion the bars stay still.
class VoiceWave extends StatefulWidget {
  const VoiceWave({this.height = 44, this.level, super.key});

  final double height;
  final double? level;

  @override
  State<VoiceWave> createState() => _VoiceWaveState();
}

class _VoiceWaveState extends State<VoiceWave>
    with SingleTickerProviderStateMixin {
  static const _ratios = [.27, .54, .77, 1.0, .65, 1.0, .77, .54, .27];

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

  double _scale(int index) {
    if (!_controller.isAnimating) return 1;
    final phase = (_controller.value - (index - 4).abs() * .1) % 1;
    final pulse = .5 + .5 * math.cos(phase * 2 * math.pi);
    final level = widget.level;
    final depth = level == null ? .55 : .25 + .5 * level.clamp(0.0, 1.0);
    return 1 - depth + depth * pulse;
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: double.infinity,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _ratios.length; i++)
              _bar(widget.height * _ratios[i], _scale(i)),
          ],
        ),
      ),
    ),
  );

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
