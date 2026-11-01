import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/history/domain/repositories/history_repository.dart';
import 'package:marieum_app/features/history/presentation/cubit/recent_requests_cubit.dart';

/// The latest three delivered sentences, shown in the side menu.
class RecentRequestsSection extends StatelessWidget {
  const RecentRequestsSection({required this.onSelected, super.key});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = RecentRequestsCubit(context.read<HistoryRepository>());
      unawaited(cubit.load());
      return cubit;
    },
    child: BlocBuilder<RecentRequestsCubit, RecentRequestsState>(
      builder: (context, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 16),
              child: LinearProgressIndicator(),
            )
          else if (state.failure != null)
            _RecentRow(
              text: '최근 요청 다시 불러오기',
              icon: Icons.refresh,
              onTap: () =>
                  unawaited(context.read<RecentRequestsCubit>().load()),
            )
          else if (state.entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Text(
                '최근 요청이 없어요',
                style: TextStyle(fontSize: 14, color: AppTokens.ink3),
              ),
            )
          else
            for (final entry in state.entries)
              _RecentRow(
                text: entry.text,
                icon: Icons.schedule_outlined,
                onTap: () => onSelected(entry.text),
              ),
        ],
      ),
    ),
  );
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.text,
    required this.icon,
    required this.onTap,
  });

  final String text;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Icon(icon, size: 18, color: AppTokens.ink3),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTokens.ink2,
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
