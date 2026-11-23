import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';
import 'package:marieum_app/features/listen/presentation/cubit/listen_host_cubit.dart';
import 'package:marieum_app/features/listen/presentation/widgets/listen_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ListenHostView extends StatelessWidget {
  const ListenHostView({
    required this.onClose,
    required this.onBack,
    super.key,
  });

  final VoidCallback onClose;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ListenHostCubit, ListenHostState>(
        builder: (context, state) => ListenScreen(
          title: '상대방 폰',
          closeLabel: state.phase == ListenHostPhase.ended ? '닫기' : '연결 끊기',
          onClose: onClose,
          onBack: onBack,
          children: switch (state.phase) {
            ListenHostPhase.creating => [
              const ListenStatusMessage('연결을 준비하고 있어요', loading: true),
            ],
            ListenHostPhase.waiting => [
              _JoinCard(
                code: state.session!.joinCode,
                remaining: state.joinRemaining,
              ),
            ],
            ListenHostPhase.connected => [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 48,
                color: AppTokens.success,
              ),
              const SizedBox(height: 12),
              const ListenStatusMessage('상대방 폰과 연결됐어요'),
              const SizedBox(height: 20),
              FilledButton(
                style: ListenScreen.primaryButton,
                onPressed: onBack,
                child: const Text('돌아가서 말하기'),
              ),
            ],
            ListenHostPhase.codeExpired ||
            ListenHostPhase.left ||
            ListenHostPhase.failed => [
              ListenStatusMessage(switch (state.phase) {
                ListenHostPhase.codeExpired => '이 코드는 더 쓸 수 없어요',
                ListenHostPhase.left => '상대방 폰 연결이 끊겼어요',
                _ => '코드를 만들지 못했어요',
              }),
              const SizedBox(height: 20),
              FilledButton(
                style: ListenScreen.primaryButton,
                onPressed: context.read<ListenHostCubit>().renew,
                child: const Text('새 코드 만들기'),
              ),
            ],
            ListenHostPhase.ended => [
              const ListenStatusMessage('연결이 끝났어요'),
            ],
          },
        ),
      );
}

class _JoinCard extends StatelessWidget {
  const _JoinCard({required this.code, required this.remaining});

  final String code;
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    final clock =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    final displayCode = code.length == JoinCode.length
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        border: Border.all(color: AppTokens.line),
        borderRadius: BorderRadius.circular(AppTokens.cardRadius),
      ),
      child: Column(
        children: [
          const Text(
            '상대방 폰에서 마리음 앱 → 상대방 말 듣기로 QR을 찍어 주세요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: AspectRatio(
              aspectRatio: 1,
              child: QrImageView(
                data: JoinCode.qrPayload(code),
                padding: const EdgeInsets.all(18),
                backgroundColor: AppTokens.surface,
                semanticsLabel: '연결 QR 코드',
              ),
            ),
          ),
          Semantics(
            label: '연결 코드 ${code.split('').join(' ')}',
            excludeSemantics: true,
            child: Text(
              displayCode,
              textAlign: TextAlign.center,
              style: AppTokens.phrase.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            label: '남은 시간 ${seconds ~/ 60}분 ${seconds % 60}초',
            excludeSemantics: true,
            child: Text(
              '남은 시간 $clock',
              style: const TextStyle(
                fontSize: 18,
                color: AppTokens.ink2,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
