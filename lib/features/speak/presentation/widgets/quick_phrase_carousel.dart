import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/router/app_routes.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/quick_phrase.dart';
import 'package:marieum_app/features/quick_phrase/presentation/bloc/quick_phrase_bloc.dart';
import 'package:marieum_app/features/quick_phrase/presentation/widgets/quick_phrase_icon.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';

class QuickPhraseCarousel extends StatefulWidget {
  const QuickPhraseCarousel({
    this.enabled = true,
    this.idleDelay = const Duration(seconds: 7),
    this.repeatGap = const Duration(seconds: 30),
    super.key,
  });

  final bool enabled;
  final Duration idleDelay;
  final Duration repeatGap;

  @override
  State<QuickPhraseCarousel> createState() => _QuickPhraseCarouselState();
}

class _QuickPhraseCarouselState extends State<QuickPhraseCarousel>
    with SingleTickerProviderStateMixin {
  static const _cardOffset = 32.0;

  late final _nudge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final Animation<double> _offset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: -_cardOffset), weight: 28),
    TweenSequenceItem(tween: Tween(begin: -_cardOffset, end: 0), weight: 24),
    TweenSequenceItem(tween: Tween(begin: 0, end: -12), weight: 18),
    TweenSequenceItem(tween: Tween(begin: -12, end: 0), weight: 30),
  ]).animate(CurvedAnimation(parent: _nudge, curve: Curves.easeOutCubic));

  Timer? _idle;
  Timer? _gap;
  bool _pendingAfterGap = false;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _arm(widget.idleDelay);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _idle?.cancel();
    _gap?.cancel();
    _nudge.dispose();
    super.dispose();
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) _arm(widget.idleDelay);
  }

  void _arm(Duration delay) {
    _pendingAfterGap = false;
    _idle?.cancel();
    _idle = Timer(delay, _runNudge);
  }

  bool get _canNudge {
    if (!mounted || !widget.enabled) return false;
    if (!TickerMode.valuesOf(context).enabled) return false;
    if (MediaQuery.disableAnimationsOf(context)) return false;
    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) return false;
    return ModalRoute.of(context)?.isCurrent ?? true;
  }

  void _runNudge() {
    if (!_canNudge) {
      _arm(widget.idleDelay);
      return;
    }
    if (_gap?.isActive ?? false) {
      _pendingAfterGap = true;
      return;
    }
    _gap = Timer(widget.repeatGap, () {
      if (_pendingAfterGap) {
        _pendingAfterGap = false;
        _runNudge();
      }
    });
    unawaited(_nudge.forward(from: 0));
  }

  void _play(QuickPhrase phrase) {
    context.read<QuickPhraseBloc>().add(QuickPhraseUsed(phrase));
    unawaited(
      context.push<void>(
        AppRoutes.playback,
        extra: PlaybackRequest(
          text: phrase.text,
          origin: PlaybackOrigin.quickPhrase,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phrases = context.select<QuickPhraseBloc, List<QuickPhrase>>(
      (bloc) => bloc.state.phrases,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '빠른 문장',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppTokens.ink,
              ),
            ),
            AnimatedBuilder(
              animation: _nudge,
              builder: (context, _) => Text(
                '옆으로 넘겨 더 보기',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _nudge.isAnimating
                      ? AppTokens.primaryStrong
                      : AppTokens.ink3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: MediaQuery.textScalerOf(context).scale(16) / 16 * 112,
            child: ListView.separated(
              key: const ValueKey('quick_phrase_carousel'),
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.only(bottom: 6),
              itemCount: phrases.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => AnimatedBuilder(
                animation: _offset,
                builder: (context, child) => Transform.translate(
                  offset: Offset(index < 3 ? _offset.value : 0, 0),
                  child: child,
                ),
                child: SizedBox(
                  width: (constraints.maxWidth - 10) / 2,
                  child: _PhraseTile(
                    phrase: phrases[index],
                    tinted: index % 3 == 0,
                    onTap: widget.enabled ? () => _play(phrases[index]) : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PhraseTile extends StatelessWidget {
  const _PhraseTile({
    required this.phrase,
    required this.tinted,
    required this.onTap,
  });

  final QuickPhrase phrase;
  final bool tinted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: '${phrase.text}, 눌러서 바로 재생',
    excludeSemantics: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: tinted
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTokens.surface, Color(0xFFF2F6FF)],
              )
            : null,
        color: tinted ? null : AppTokens.surface,
        border: Border.all(color: AppTokens.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A17233D),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('quick_phrase_${phrase.id}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTokens.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    quickPhraseIconData(phrase.icon),
                    size: 20,
                    color: AppTokens.primaryStrong,
                  ),
                ),
                Text(
                  phrase.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.3,
                    letterSpacing: -.32,
                    fontWeight: FontWeight.w800,
                    color: AppTokens.ink,
                  ),
                ),
                const Text(
                  '눌러서 바로 재생',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.ink3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
