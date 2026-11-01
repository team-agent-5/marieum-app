import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_segmented_control.dart';
import 'package:marieum_app/core/ui/feature_panel.dart';
import 'package:marieum_app/core/ui/key_text.dart';
import 'package:marieum_app/features/history/domain/entities/history_range.dart';
import 'package:marieum_app/features/history/presentation/cubit/history_cubit.dart';
import 'package:marieum_app/features/history/presentation/widgets/history_entry_tile.dart';

class HistoryView extends StatelessWidget {
  const HistoryView({super.key});
  @override
  Widget build(BuildContext context) => BlocBuilder<HistoryCubit, HistoryState>(
    builder: (context, state) => ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '전달한 문장을 다시 듣거나\n최근 사용 흐름을 확인할 수 있어요.',
                style: AppTokens.copy,
              ),
            ),
            Chip(label: Text('${state.total}건')),
          ],
        ),
        const SizedBox(height: 14),
        AdaptiveSegmentedControl<HistoryRange>(
          value: state.range,
          children: const {
            HistoryRange.today: Text('오늘'),
            HistoryRange.week: Text('지난 7일'),
          },
          onChanged: (range) =>
              unawaited(context.read<HistoryCubit>().load(range)),
        ),
        const SizedBox(height: 14),
        if (state.status == HistoryStatus.loading && state.entries.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (state.entries.isEmpty && state.failure == null)
          const _EmptyHistory()
        else if (state.entries.isNotEmpty)
          FeaturePanel(
            child: Column(
              children: [
                for (final entry in state.entries)
                  HistoryEntryTile(entry: entry),
              ],
            ),
          ),
        if (state.failure != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Text(state.failure!.message),
                TextButton(
                  onPressed: () => unawaited(
                    state.entries.isEmpty
                        ? context.read<HistoryCubit>().load()
                        : context.read<HistoryCubit>().more(),
                  ),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        if (state.nextCursor != null)
          TextButton(
            onPressed: state.status == HistoryStatus.loading
                ? null
                : () => unawaited(context.read<HistoryCubit>().more()),
            child: Text(
              state.status == HistoryStatus.loading ? '불러오는 중…' : '더 보기',
            ),
          ),
      ],
    ),
  );
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 72),
    child: Column(
      children: [
        const Icon(
          Icons.receipt_long_outlined,
          size: 64,
          color: AppTokens.primaryStrong,
        ),
        const SizedBox(height: 16),
        const Text('아직 기록이 없어요', style: AppTokens.title),
        const Text(
          '말하기나 빠른 문장을 사용하면\n여기에 차곡차곡 모여요.',
          textAlign: TextAlign.center,
          style: AppTokens.copy,
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () => context.go('/speak'),
          child: const KeyText('말하기 시작'),
        ),
      ],
    ),
  );
}
