import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/quick_phrase.dart';
import 'package:marieum_app/features/quick_phrase/presentation/bloc/quick_phrase_bloc.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:marieum_app/features/speak/presentation/bloc/utterance_bloc.dart';

/// Bottom sheet content for candidates, re-ask, no-match and speaking.
/// Popping with a [QuickPhrase] asks the caller to play that phrase.
class UtteranceSheet extends StatelessWidget {
  const UtteranceSheet({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<UtteranceBloc, UtteranceState>(
        buildWhen: (previous, current) => current.phase.usesSheet,
        builder: (context, state) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Handle(),
                const SizedBox(height: 14),
                switch (state.phase) {
                  UtterancePhase.suggesting => _Candidates(state: state),
                  UtterancePhase.reask when state.reaskExhausted =>
                    const _ReaskExhausted(),
                  UtterancePhase.reask => _Reask(state: state),
                  UtterancePhase.speaking => _Speaking(
                    text: state.spokenText ?? '',
                  ),
                  _ => _NoMatch(state: state),
                },
              ],
            ),
          ),
        ),
      );
}

class _Handle extends StatelessWidget {
  const _Handle();
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 5,
      decoration: BoxDecoration(
        color: AppTokens.lineStrong,
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  );
}

class _Candidates extends StatelessWidget {
  const _Candidates({required this.state});
  final UtteranceState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<UtteranceBloc>();
    final candidates = state.suggestions?.candidates ?? const <Candidate>[];
    final selected = state.selected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '들린 내용 · ${state.transcription?.heard ?? ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTokens.ink3,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          header: true,
          child: const Text(
            '이렇게 말씀하시려는 거예요?',
            style: TextStyle(
              fontSize: 20,
              height: 1.35,
              fontWeight: FontWeight.w800,
              color: AppTokens.ink,
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final candidate in candidates) ...[
          _CandidateTile(
            candidate: candidate,
            selected: candidate == selected,
            onTap: () => bloc.add(UtteranceCandidateTapped(candidate)),
          ),
          const SizedBox(height: 9),
        ],
        const SizedBox(height: 4),
        if (selected != null) ...[
          FilledButton.icon(
            key: const ValueKey('utterance_confirm'),
            onPressed: () => bloc.add(const UtteranceConfirmPressed()),
            icon: const Icon(Icons.volume_up_rounded),
            label: const Text('이 말로 말하기'),
          ),
          const SizedBox(height: 9),
        ],
        _SecondaryButton(
          key: const ValueKey('utterance_retry'),
          icon: Icons.mic_none_rounded,
          label: '다시 말하기',
          onPressed: () => bloc.add(const UtteranceRetryPressed()),
        ),
      ],
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final Candidate candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reason = reasonText(candidate);
    return Semantics(
      button: true,
      selected: selected,
      label: [
        '${candidate.rank}번',
        candidate.text,
        ?reason,
        if (selected) '선택됨',
      ].join(', '),
      excludeSemantics: true,
      child: Material(
        color: selected ? AppTokens.surfaceBlue : AppTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(
            color: selected ? AppTokens.primary : AppTokens.line,
            width: selected ? 2 : 1.5,
          ),
        ),
        child: InkWell(
          key: ValueKey('candidate_${candidate.rank}'),
          borderRadius: BorderRadius.circular(17),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 78),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppTokens.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${candidate.rank}',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: AppTokens.onTonal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidate.text,
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.3,
                            fontWeight: FontWeight.w800,
                            color: AppTokens.ink,
                          ),
                        ),
                        if (reason != null) ...[
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome_outlined,
                                size: 14,
                                color: AppTokens.ink2,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  reason,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTokens.ink2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 9),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 24,
                    color: selected ? AppTokens.primary : AppTokens.lineStrong,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Server-provided Korean label first; local wording only as a fallback.
String? reasonText(Candidate candidate) =>
    candidate.reasonDisplay ??
    switch (candidate.reasonLabel) {
      'registered_preference' => '등록한 선호',
      'time_context' => '이 시간대에 자주 선택',
      'recency' => '최근 요청',
      'patient_frequency' => '자주 쓰는 말',
      'sequence_context' => '다음에 자주 하는 말',
      'semantic_similarity' => '비슷한 말투',
      _ => null,
    };

class _Reask extends StatelessWidget {
  const _Reask({required this.state});
  final UtteranceState state;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _AttemptBars(count: state.reaskCount),
      const _Recovery(
        icon: Icons.refresh_rounded,
        kicker: '소리가 조금 흐렸어요',
        title: '한 번만 다시 말씀해 주세요',
        body: '조금 천천히 말하면 더 정확하게 알아들을 수 있어요.',
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTokens.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTokens.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '이렇게 들렸어요',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTokens.ink3,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              state.transcription?.heard ?? '',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTokens.ink,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        key: const ValueKey('reask_retry'),
        onPressed: () =>
            context.read<UtteranceBloc>().add(const UtteranceRetryPressed()),
        icon: const Icon(Icons.mic_rounded),
        label: const Text('다시 말하기'),
      ),
      const SizedBox(height: 9),
      _SecondaryButton(
        icon: Icons.grid_view_rounded,
        label: '빠른 문장에서 선택',
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

class _ReaskExhausted extends StatelessWidget {
  const _ReaskExhausted();

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _AttemptBars(count: UtteranceBloc.maxReask),
      _Recovery(
        icon: Icons.list_alt_rounded,
        kicker: '다른 방법을 써볼게요',
        title: '원하는 문장을 골라 주세요',
        body: '자주 사용하는 문장을 바로 재생할 수 있어요.',
      ),
      _QuickOptions(moreLabel: '빠른 문장 더 보기'),
    ],
  );
}

class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.state});
  final UtteranceState state;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _Recovery(
        icon: Icons.list_alt_rounded,
        kicker: '알맞은 문장을 찾지 못했어요',
        title: '원하시는 말이 아래에 있나요?',
        body: '빠른 문장에서 골라 주세요.',
      ),
      const _QuickOptions(moreLabel: '빠른 문장 더 보기'),
      const SizedBox(height: 9),
      _SecondaryButton(
        icon: Icons.mic_none_rounded,
        label: '다시 말하기',
        onPressed: () =>
            context.read<UtteranceBloc>().add(const UtteranceRetryPressed()),
      ),
    ],
  );
}

class _Speaking extends StatelessWidget {
  const _Speaking({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: '말하고 있어요. $text',
    excludeSemantics: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 160),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTokens.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTokens.primary, width: 2),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 30,
              height: 1.25,
              letterSpacing: -1.2,
              fontWeight: FontWeight.w900,
              color: AppTokens.ink,
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.volume_up_rounded, color: AppTokens.primaryStrong),
            SizedBox(width: 8),
            Text(
              '말하고 있어요',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTokens.primaryStrong,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
}

class _Recovery extends StatelessWidget {
  const _Recovery({
    required this.icon,
    required this.kicker,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String kicker;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
    child: Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: AppTokens.primarySoft,
            borderRadius: BorderRadius.circular(21),
          ),
          child: Icon(icon, size: 30, color: AppTokens.primaryStrong),
        ),
        const SizedBox(height: 10),
        Text(
          kicker,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppTokens.primaryStrong,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              height: 1.3,
              letterSpacing: -.72,
              fontWeight: FontWeight.w800,
              color: AppTokens.ink,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.center,
          style: AppTokens.copy,
        ),
      ],
    ),
  );
}

class _AttemptBars extends StatelessWidget {
  const _AttemptBars({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '다시 듣기 $count / ${UtteranceBloc.maxReask}회',
    excludeSemantics: true,
    child: Row(
      children: [
        for (var i = 0; i < UtteranceBloc.maxReask; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i < count ? AppTokens.primary : AppTokens.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _QuickOptions extends StatelessWidget {
  const _QuickOptions({required this.moreLabel});
  final String moreLabel;

  @override
  Widget build(BuildContext context) {
    final phrases = context.select<QuickPhraseBloc, List<QuickPhrase>>(
      (bloc) => bloc.state.phrases.take(3).toList(growable: false),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final phrase in phrases) ...[
          Material(
            color: AppTokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: const BorderSide(color: AppTokens.line),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: () => Navigator.of(context).pop(phrase),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          phrase.text,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTokens.ink,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.volume_up_rounded,
                        size: 20,
                        color: AppTokens.primaryStrong,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            foregroundColor: AppTokens.primaryStrong,
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: Text(moreLabel),
        ),
      ],
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(AppTokens.buttonHeight),
      foregroundColor: AppTokens.onTonal,
      side: const BorderSide(color: AppTokens.lineStrong),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.buttonRadius),
      ),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    ),
  );
}
