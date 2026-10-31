import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/audio/speech_segmenter.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_top_bar.dart';
import 'package:marieum_app/features/speak/presentation/cubit/live_session_cubit.dart';
import 'package:marieum_app/features/speak/presentation/widgets/typed_transcript.dart';

/// Live mode: listens continuously and adds each interpreted sentence as
/// soon as the server returns it.
class LiveSessionView extends StatelessWidget {
  const LiveSessionView({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return Scaffold(
      backgroundColor: AppTokens.bg,
      appBar: AdaptiveTopBar(
        title: '내 목소리로 말하기',
        leading: ios
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: onClose,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.chevron_back, size: 22),
                    Text('뒤로'),
                  ],
                ),
              )
            : IconButton(
                tooltip: '뒤로',
                onPressed: onClose,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
      ),
      body: SafeArea(
        top: false,
        child: BlocBuilder<LiveSessionCubit, LiveSessionState>(
          builder: (context, state) => Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: state.status == LiveStatus.failed
                ? _Failed(state: state, onClose: onClose)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(state: state),
                      const SizedBox(height: 16),
                      Expanded(child: _Transcript(state: state)),
                      const SizedBox(height: 18),
                      InputSignal(
                        levels: state.levels,
                        hearing: state.hearing,
                        threshold: state.threshold,
                        muted: state.playing,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        state.playing
                            ? '전달하는 동안은 잠시 듣지 않아요'
                            : state.hearing
                            ? '목소리가 들려요'
                            : '말씀하시면 바로 해석해요',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTokens.ink2,
                        ),
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        key: const ValueKey('live_stop'),
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('그만하기'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(
                            AppTokens.buttonHeight,
                          ),
                          foregroundColor: AppTokens.ink,
                          backgroundColor: AppTokens.surface,
                          side: const BorderSide(color: AppTokens.line),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTokens.buttonRadius,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});
  final LiveSessionState state;

  @override
  Widget build(BuildContext context) {
    final seconds = state.elapsed.inSeconds;
    final clock =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '실시간 모드',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTokens.warning,
                ),
              ),
              Semantics(
                header: true,
                child: Text(
                  state.status == LiveStatus.starting
                      ? '준비하고 있어요'
                      : state.playing
                      ? '전달하고 있어요'
                      : '듣고 있어요',
                  style: AppTokens.title,
                ),
              ),
            ],
          ),
        ),
        if (state.status == LiveStatus.listening)
          Semantics(
            label: '$seconds초 동안 듣는 중',
            excludeSemantics: true,
            child: Row(
              children: [
                const _BlinkingDot(),
                const SizedBox(width: 7),
                Text(
                  clock,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTokens.primaryStrong,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Subtitle layout: the newest sentence large at the bottom, earlier ones
/// small above it so a listener can read the current one from a distance.
class _Transcript extends StatelessWidget {
  const _Transcript({required this.state});
  final LiveSessionState state;

  @override
  Widget build(BuildContext context) {
    final segments = state.segments;
    return Container(
      key: const ValueKey('live_transcript'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTokens.surface, Color(0xFFF5F8FF)],
        ),
        border: Border.all(color: AppTokens.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D17233D),
            blurRadius: 20,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  '해석한 문장',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTokens.primaryStrong,
                  ),
                ),
              ),
              Text(
                '음성은 저장하지 않아요',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.ink3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The newest sentence sits in the middle while there is room and
          // is pushed down as earlier ones pile up above it.
          Expanded(
            child: segments.isEmpty
                ? const Center(
                    child: Text(
                      '말씀하시면 해석한 문장이 여기에 바로 나와요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.ink3,
                      ),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (segments.length > 1) ...[
                        Flexible(
                          child: AnimatedSize(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.bottomCenter,
                            child: _History(
                              segments: segments.sublist(
                                0,
                                segments.length - 1,
                              ),
                              playingId: state.playingId,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _Current(
                        segment: segments.last,
                        playing: state.playingId == segments.last.id,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _History extends StatefulWidget {
  const _History({required this.segments, required this.playingId});
  final List<LiveSegment> segments;
  final int? playingId;

  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_History oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segments.length == widget.segments.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(end);
      } else {
        unawaited(
          _scroll.animateTo(
            end,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      controller: _scroll,
      shrinkWrap: true,
      itemCount: widget.segments.length,
      itemBuilder: (context, index) {
        final segment = widget.segments[index];
        return _HistoryLine(
          key: ValueKey(segment.id),
          segment: segment,
          playing: widget.playingId == segment.id,
        );
      },
    );
    if (widget.segments.length <= 3) return list;
    // Once lines pile up, the oldest fade out toward the top.
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x33000000), Color(0xFF000000)],
        stops: [0, .45],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: list,
    );
  }
}

class _HistoryLine extends StatelessWidget {
  const _HistoryLine({
    required this.segment,
    required this.playing,
    super.key,
  });

  final LiveSegment segment;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final done = segment.status == LiveSegmentStatus.done;
    final time =
        '${segment.at.hour.toString().padLeft(2, '0')}:'
        '${segment.at.minute.toString().padLeft(2, '0')}';
    final (text, color) = switch (segment.status) {
      LiveSegmentStatus.done => (segment.text, AppTokens.ink2),
      LiveSegmentStatus.interpreting => (
        segment.text.isEmpty ? '해석하고 있어요' : segment.text,
        AppTokens.ink3,
      ),
      LiveSegmentStatus.unclear => ('잘 알아듣지 못했어요', AppTokens.ink3),
      LiveSegmentStatus.failed => (segment.text, AppTokens.danger),
    };
    return Semantics(
      button: done,
      label: done ? '$time $text, 다시 듣기' : '$time $text',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: done
            ? () => unawaited(
                context.read<LiveSessionCubit>().replay(segment.id),
              )
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    time,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTokens.ink3,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: done ? 17 : 15,
                      height: 1.35,
                      fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
                if (done)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      playing ? Icons.volume_up_rounded : Icons.replay_rounded,
                      size: 20,
                      color: playing ? AppTokens.primaryStrong : AppTokens.ink3,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The newest sentence, large. A new one rises in from below.
class _Current extends StatelessWidget {
  const _Current({required this.segment, required this.playing});
  final LiveSegment segment;
  final bool playing;

  static const _style = TextStyle(
    fontSize: 30,
    height: 1.3,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.9,
    color: AppTokens.ink,
  );

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, .25),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(
        key: ValueKey(segment.id),
        child: _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) => switch (segment.status) {
    LiveSegmentStatus.interpreting when segment.text.isNotEmpty => Semantics(
      liveRegion: true,
      child: Text(segment.text, style: _style.copyWith(color: AppTokens.ink2)),
    ),
    LiveSegmentStatus.interpreting => const Row(
      children: [
        SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        SizedBox(width: 12),
        Text(
          '해석하고 있어요',
          style: TextStyle(fontSize: 18, color: AppTokens.ink2),
        ),
      ],
    ),
    LiveSegmentStatus.done => Semantics(
      liveRegion: true,
      button: true,
      label: '${segment.text}, 다시 듣기',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            unawaited(context.read<LiveSessionCubit>().replay(segment.id)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TypedTranscript(
                text: segment.text,
                caret: false,
                style: _style,
              ),
            ),
            if (playing)
              const Padding(
                padding: EdgeInsets.only(left: 8, top: 8),
                child: Icon(
                  Icons.volume_up_rounded,
                  color: AppTokens.primaryStrong,
                ),
              ),
          ],
        ),
      ),
    ),
    LiveSegmentStatus.unclear => const Text(
      '잘 알아듣지 못했어요. 다시 말씀해 주세요',
      style: TextStyle(fontSize: 20, height: 1.4, color: AppTokens.ink3),
    ),
    LiveSegmentStatus.failed => Text(
      segment.text,
      style: const TextStyle(
        fontSize: 18,
        height: 1.4,
        color: AppTokens.danger,
      ),
    ),
  };
}

/// Live input loudness as bars, newest on the right. Bars above the voice
/// threshold are drawn in the accent color so the patient can see that
/// they are being heard.
class InputSignal extends StatelessWidget {
  const InputSignal({
    required this.levels,
    required this.hearing,
    required this.muted,
    this.threshold = SpeechSegmenter.defaultThreshold,
    super.key,
  });

  final List<double> levels;
  final bool hearing;
  final bool muted;
  final double threshold;

  static const height = 64.0;

  @override
  Widget build(BuildContext context) {
    final padded = [
      for (var i = levels.length; i < LiveSessionCubit.historyLength; i++) 0.0,
      ...levels,
    ];
    return ExcludeSemantics(
      child: SizedBox(
        key: const ValueKey('live_signal'),
        height: height,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final level in padded)
              AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 90),
                width: 5,
                height: 4 + level.clamp(0.0, 1.0) * (height - 4),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: muted
                      ? AppTokens.line
                      : level >= threshold
                      ? AppTokens.primary
                      : AppTokens.lineStrong,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.state, required this.onClose});
  final LiveSessionState state;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(Icons.mic_off_rounded, size: 40, color: AppTokens.danger),
      const SizedBox(height: 12),
      const Text(
        '마이크를 쓸 수 없어요',
        textAlign: TextAlign.center,
        style: AppTokens.title,
      ),
      const SizedBox(height: 6),
      Text(
        state.failure?.message ?? '',
        textAlign: TextAlign.center,
        style: AppTokens.copy,
      ),
      const SizedBox(height: 20),
      OutlinedButton(onPressed: onClose, child: const Text('닫기')),
    ],
  );
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();
  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) =>
        Opacity(opacity: _controller.value < .5 ? 1 : .28, child: child),
    child: Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: AppTokens.primaryStrong,
        shape: BoxShape.circle,
      ),
    ),
  );
}
