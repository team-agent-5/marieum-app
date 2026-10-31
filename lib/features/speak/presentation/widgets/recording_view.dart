import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/audio/recorder.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_top_bar.dart';
import 'package:marieum_app/features/speak/domain/entities/speak_mode.dart';
import 'package:marieum_app/features/speak/presentation/bloc/utterance_bloc.dart';
import 'package:marieum_app/features/speak/presentation/widgets/voice_wave.dart';

/// Full-screen recording: elapsed time, the live transcript and the controls
/// to finish or cancel. Leaving the screen cancels the recording.
class RecordingView extends StatelessWidget {
  const RecordingView({super.key});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<UtteranceBloc>();
    void cancel() => bloc.add(const UtteranceCancelPressed());
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) cancel();
      },
      child: Scaffold(
        backgroundColor: AppTokens.bg,
        appBar: AdaptiveTopBar(
          title: '내 목소리로 말하기',
          leading: ios
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: cancel,
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
                  onPressed: cancel,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
        ),
        body: SafeArea(
          top: false,
          child: BlocBuilder<UtteranceBloc, UtteranceState>(
            buildWhen: (previous, current) => current.phase.locksScreen,
            builder: (context, state) {
              final live = state.mode == SpeakMode.live;
              final analyzing = state.phase == UtterancePhase.analyzing;
              return Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      live: live,
                      analyzing: analyzing,
                      elapsed: state.elapsed,
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: _TranscriptCard(
                          available: state.liveTextAvailable,
                          text: state.liveText,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (analyzing)
                      const SizedBox(
                        height: 58,
                        child: Center(
                          child: SizedBox.square(
                            dimension: 34,
                            child: CircularProgressIndicator(strokeWidth: 3.5),
                          ),
                        ),
                      )
                    else
                      VoiceWave(height: 58, level: state.level),
                    const SizedBox(height: 4),
                    Text(
                      analyzing
                          ? '말씀하신 내용을 확인하고 있어요'
                          : live
                          ? '녹음을 끝내면 바로 음성으로 전달해요'
                          : '계속 말씀해 주세요',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTokens.ink2,
                      ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      key: const ValueKey('recording_finish'),
                      onPressed: analyzing
                          ? null
                          : () => bloc.add(UtteranceButtonPressed(state.mode)),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(
                          AppTokens.buttonHeight,
                        ),
                        backgroundColor: AppTokens.primaryStrong,
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTokens.buttonRadius,
                          ),
                        ),
                      ),
                      child: Text(analyzing ? '확인하고 있어요' : '녹음 끝내기'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const ValueKey('recording_cancel'),
                      onPressed: cancel,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('취소'),
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
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.live,
    required this.analyzing,
    required this.elapsed,
  });
  final bool live;
  final bool analyzing;
  final Duration elapsed;

  static String _clock(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final seconds = elapsed.inSeconds;
    final limit = Recorder.maxDuration.inSeconds;
    final modeColor = live ? AppTokens.warning : AppTokens.primaryStrong;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    live ? '실시간 모드' : '정확도 모드',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: modeColor,
                    ),
                  ),
                  Semantics(
                    header: true,
                    child: Text(
                      analyzing ? '알아듣고 있어요' : '듣고 있어요',
                      style: AppTokens.title,
                    ),
                  ),
                ],
              ),
            ),
            if (!analyzing)
              Semantics(
                label: '녹음 $seconds초, 최대 $limit초',
                excludeSemantics: true,
                child: Row(
                  children: [
                    const _BlinkingDot(),
                    const SizedBox(width: 7),
                    Text(
                      '${_clock(seconds)} / ${_clock(limit)}',
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
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            key: const ValueKey('recording_limit'),
            minHeight: 4,
            value: analyzing
                ? 1
                : (elapsed.inMilliseconds / Recorder.maxDuration.inMilliseconds)
                      .clamp(0.0, 1.0),
            color: AppTokens.primary,
            backgroundColor: AppTokens.primarySoft,
          ),
        ),
      ],
    );
  }
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

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({required this.available, required this.text});
  final bool available;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 178),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (available) ...[
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppTokens.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                available ? '실시간 텍스트' : '말씀하신 내용',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTokens.primaryStrong,
                ),
              ),
            ),
            const Text(
              '음성은 저장하지 않아요',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTokens.ink3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (available)
          Semantics(
            liveRegion: true,
            label: text,
            excludeSemantics: true,
            child: TypedTranscript(text: text),
          )
        else
          const Text(
            '말씀을 마치면 글자로 바꿔 드려요',
            style: TextStyle(
              fontSize: 20,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: AppTokens.ink3,
            ),
          ),
        const SizedBox(height: 18),
        Text(
          available
              ? '말씀하신 내용이 자연스럽게 이어서 표시돼요.'
              : '이 기기에서는 말하는 동안 글자를 보여 줄 수 없어요.',
          style: const TextStyle(fontSize: 12, color: AppTokens.ink3),
        ),
      ],
    ),
  );
}

/// Shows recognized words as they arrive. Words that extend the previous
/// text fade and rise in; a blinking caret marks where speech continues.
class TypedTranscript extends StatefulWidget {
  const TypedTranscript({required this.text, super.key});
  final String text;

  static const style = TextStyle(
    fontSize: 24,
    height: 1.5,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    color: AppTokens.ink,
  );

  @override
  State<TypedTranscript> createState() => _TypedTranscriptState();
}

class _TypedTranscriptState extends State<TypedTranscript> {
  /// Each word keeps a stable id while it stays the same, so only new or
  /// corrected words animate.
  final _words = <({int id, String word})>[];
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    _sync(widget.text);
  }

  @override
  void didUpdateWidget(TypedTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _sync(widget.text);
  }

  void _sync(String text) {
    final next = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    var index = 0;
    final kept = <({int id, String word})>[];
    for (final word in next) {
      if (index < _words.length && _words[index].word == word) {
        kept.add(_words[index]);
      } else {
        kept.add((id: _nextId++, word: word));
      }
      index++;
    }
    _words
      ..clear()
      ..addAll(kept);
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 7,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final entry in _words)
        _TypedWord(key: ValueKey(entry.id), word: entry.word),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '…',
            style: TypedTranscript.style.copyWith(
              color: AppTokens.ink3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          const _Caret(),
        ],
      ),
    ],
  );
}

class _TypedWord extends StatefulWidget {
  const _TypedWord({required this.word, super.key});
  final String word;
  @override
  State<_TypedWord> createState() => _TypedWordState();
}

class _TypedWordState extends State<_TypedWord>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.isDismissed) {
      unawaited(_controller.forward());
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
    builder: (context, child) {
      final t = Curves.easeOut.transform(_controller.value);
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 5 * (1 - t)),
          child: child,
        ),
      );
    },
    child: Text(widget.word, style: TypedTranscript.style),
  );
}

class _Caret extends StatefulWidget {
  const _Caret();
  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
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
        Opacity(opacity: _controller.value < .5 ? 1 : 0, child: child),
    child: Container(width: 2, height: 25, color: AppTokens.primaryStrong),
  );
}
