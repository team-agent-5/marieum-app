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

/// The interpreted sentences, newest at the bottom.
class _Transcript extends StatefulWidget {
  const _Transcript({required this.state});
  final LiveSessionState state;

  @override
  State<_Transcript> createState() => _TranscriptState();
}

class _TranscriptState extends State<_Transcript> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_Transcript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.segments != widget.state.segments) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final end = _scroll.position.maxScrollExtent;
        if (MediaQuery.disableAnimationsOf(context)) {
          _scroll.jumpTo(end);
        } else {
          unawaited(
            _scroll.animateTo(
              end,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final segments = widget.state.segments;
    return Container(
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
          Expanded(
            child: segments.isEmpty
                ? const Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      '말씀하시면 해석한 문장이 여기에 바로 나와요',
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.ink3,
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: _scroll,
                    itemCount: segments.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _SegmentLine(
                      key: ValueKey(segments[index].id),
                      segment: segments[index],
                      playing: widget.state.playingId == segments[index].id,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SegmentLine extends StatelessWidget {
  const _SegmentLine({
    required this.segment,
    required this.playing,
    super.key,
  });

  final LiveSegment segment;
  final bool playing;

  static const _done = TextStyle(
    fontSize: 24,
    height: 1.4,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    color: AppTokens.ink,
  );

  @override
  Widget build(BuildContext context) => switch (segment.status) {
    LiveSegmentStatus.interpreting => const Row(
      children: [
        SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 10),
        Text(
          '해석하고 있어요',
          style: TextStyle(fontSize: 16, color: AppTokens.ink2),
        ),
      ],
    ),
    LiveSegmentStatus.done => Semantics(
      liveRegion: true,
      label: segment.text,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TypedTranscript(
              text: segment.text,
              caret: false,
              style: _done,
            ),
          ),
          if (playing)
            const Padding(
              padding: EdgeInsets.only(left: 8, top: 6),
              child: Icon(
                Icons.volume_up_rounded,
                color: AppTokens.primaryStrong,
              ),
            ),
        ],
      ),
    ),
    LiveSegmentStatus.unclear => Text(
      segment.text.isEmpty
          ? '잘 알아듣지 못했어요. 다시 말씀해 주세요'
          : '잘 알아듣지 못했어요 ("${segment.text}")',
      style: const TextStyle(fontSize: 16, color: AppTokens.ink3),
    ),
    LiveSegmentStatus.failed => Text(
      segment.text,
      style: const TextStyle(fontSize: 16, color: AppTokens.danger),
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
    super.key,
  });

  final List<double> levels;
  final bool hearing;
  final bool muted;

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
                      : level >= SpeechSegmenter.defaultThreshold
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
