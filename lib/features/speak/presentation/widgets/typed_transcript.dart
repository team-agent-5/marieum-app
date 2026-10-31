import 'dart:async';

import 'package:flutter/material.dart';
import 'package:marieum_app/core/theme/tokens.dart';

/// Shows recognized words as they arrive. Words that extend the previous
/// text fade and rise in; a blinking caret marks where speech continues.
class TypedTranscript extends StatefulWidget {
  const TypedTranscript({
    required this.text,
    this.caret = true,
    this.style = defaultStyle,
    super.key,
  });
  final String text;

  /// Shows the trailing ellipsis and blinking caret while speech goes on.
  final bool caret;
  final TextStyle style;

  static const defaultStyle = TextStyle(
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
        _TypedWord(
          key: ValueKey(entry.id),
          word: entry.word,
          style: widget.style,
        ),
      if (widget.caret)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '…',
              style: widget.style.copyWith(
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
  const _TypedWord({required this.word, required this.style, super.key});
  final String word;
  final TextStyle style;
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
    child: Text(widget.word, style: widget.style),
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
