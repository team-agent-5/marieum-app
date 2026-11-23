import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';
import 'package:marieum_app/features/listen/presentation/cubit/listener_cubit.dart';
import 'package:marieum_app/features/listen/presentation/widgets/listen_screen.dart';
import 'package:marieum_app/features/listen/presentation/widgets/listener_code_form.dart';

class ListenerView extends StatefulWidget {
  const ListenerView({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  State<ListenerView> createState() => _ListenerViewState();
}

class _ListenerViewState extends State<ListenerView> {
  bool _retrying = false;

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ListenerCubit, ListenerState>(
        listenWhen: (_, state) => state.phase == ListenerPhase.joining,
        listener: (_, _) {
          if (_retrying) setState(() => _retrying = false);
        },
        builder: (context, state) {
          // An ended cubit accepts another join directly. Reopen the form here.
          final phase = _retrying ? ListenerPhase.entering : state.phase;
          return ListenScreen(
            title: '상대방 말 듣기',
            closeLabel: switch (phase) {
              ListenerPhase.entering || ListenerPhase.ended => '닫기',
              _ => '그만 듣기',
            },
            onClose: widget.onClose,
            children: switch (phase) {
              ListenerPhase.entering => [ListenerCodeForm(error: state.error)],
              ListenerPhase.joining => [
                const ListenStatusMessage('코드를 확인하고 있어요', loading: true),
              ],
              ListenerPhase.connecting => [
                const ListenStatusMessage('연결하고 있어요', loading: true),
              ],
              ListenerPhase.listening || ListenerPhase.reconnecting => [
                if (phase == ListenerPhase.reconnecting) ...[
                  const _ReconnectingBanner(),
                  const SizedBox(height: 12),
                ],
                if (state.lines.isEmpty)
                  const ListenStatusMessage('상대방의 말을 기다리고 있어요')
                else ...[
                  _TranscriptLine(
                    line: state.lines.last,
                    playing: state.lines.last.utteranceId == state.speakingId,
                    latest: true,
                  ),
                  if (state.lines.length > 1) ...[
                    const SizedBox(height: 20),
                    const Text('지난 문장', style: AppTokens.title),
                    const SizedBox(height: 8),
                    for (final line in state.lines.reversed.skip(1))
                      _TranscriptLine(
                        key: ValueKey(line.utteranceId),
                        line: line,
                        playing: line.utteranceId == state.speakingId,
                      ),
                  ],
                ],
              ],
              ListenerPhase.ended => [
                ListenStatusMessage(switch (state.endReason) {
                  ListenEndReason.patientLeft => '환자가 대화를 끝냈어요',
                  ListenEndReason.expired => '대화가 끝났어요',
                  ListenEndReason.revoked => '환자가 새 연결을 만들었어요',
                  ListenEndReason.tokenInvalid => '연결 정보가 올바르지 않아요',
                  ListenEndReason.otherDevice => '이미 다른 기기에서 듣고 있어요',
                  ListenEndReason.connectionLost => '연결이 끊겼어요. 다시 연결해 주세요.',
                  null => '연결이 끝났어요',
                }),
                const SizedBox(height: 20),
                FilledButton(
                  style: ListenScreen.primaryButton,
                  onPressed: () => setState(() => _retrying = true),
                  child: const Text('다시 연결'),
                ),
              ],
            },
          );
        },
      );
}

class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.warningSoft,
        borderRadius: BorderRadius.circular(AppTokens.buttonRadius),
      ),
      child: const Text(
        '다시 연결하고 있어요',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppTokens.ink,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _TranscriptLine extends StatelessWidget {
  const _TranscriptLine({
    required this.line,
    required this.playing,
    this.latest = false,
    super.key,
  });

  final HeardLine line;
  final bool playing;
  final bool latest;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: latest,
    child: Container(
      margin: EdgeInsets.only(bottom: latest ? 0 : 8),
      padding: EdgeInsets.all(latest ? 20 : 14),
      decoration: BoxDecoration(
        color: playing ? AppTokens.primarySoft : AppTokens.surface,
        border: Border.all(color: AppTokens.line),
        borderRadius: BorderRadius.circular(AppTokens.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (playing)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                '재생 중',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTokens.onTonal,
                ),
              ),
            ),
          Text(
            line.text,
            style: latest
                ? AppTokens.phrase
                : AppTokens.copy.copyWith(fontSize: 18),
          ),
        ],
      ),
    ),
  );
}
