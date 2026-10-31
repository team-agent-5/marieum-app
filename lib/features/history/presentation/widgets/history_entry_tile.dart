import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/key_text.dart';
import 'package:marieum_app/features/history/domain/entities/history_entry.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';

class HistoryEntryTile extends StatelessWidget {
  const HistoryEntryTile({required this.entry, super.key});
  final HistoryEntry entry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
    child: Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            DateFormat('HH:mm').format(entry.createdAt.toLocal()),
            style: const TextStyle(fontSize: 12, color: AppTokens.ink2),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeyText(
                entry.text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.ink,
                ),
              ),
              const Text(
                '음성으로 전달됨',
                style: TextStyle(fontSize: 11, color: AppTokens.ink2),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '${entry.text} 다시 재생',
          icon: const Icon(
            Icons.volume_up_outlined,
            color: AppTokens.primaryStrong,
          ),
          onPressed: () => unawaited(
            context.push<void>(
              '/speak/playback',
              extra: PlaybackRequest(
                text: entry.text,
                origin: PlaybackOrigin.history,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
