import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:marieum_app/features/speak/presentation/cubit/playback_cubit.dart';

class ProactiveSuggestionDialog extends StatelessWidget {
  const ProactiveSuggestionDialog({required this.suggestion, super.key});
  final ProactiveSuggestion suggestion;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ModalBarrier(
        color: Colors.black38,
        semanticsLabel: '추천 닫기',
        onDismiss: context.read<PlaybackCubit>().declineSuggestion,
      ),
      Center(
        child: AlertDialog(
          backgroundColor: AppTokens.surface,
          title: Text(suggestion.modalText),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppTokens.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  suggestion.candidate.text,
                  style: const TextStyle(
                    fontSize: 28,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    color: AppTokens.ink,
                  ),
                ),
              ),
              if (suggestion.candidate.reasonDisplay != null) ...[
                const SizedBox(height: 10),
                Text(
                  suggestion.candidate.reasonDisplay!,
                  style: AppTokens.copy,
                ),
              ],
              const SizedBox(height: 12),
              const Text('3초 동안 선택하지 않으면 닫혀요.', style: AppTokens.copy),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(76, 52)),
              onPressed: context.read<PlaybackCubit>().declineSuggestion,
              child: const Text('아니오'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(76, 52)),
              onPressed: () =>
                  unawaited(context.read<PlaybackCubit>().acceptSuggestion()),
              child: const Text('네'),
            ),
          ],
        ),
      ),
    ],
  );
}
