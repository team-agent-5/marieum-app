import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/history/domain/repositories/history_repository.dart';
import 'package:marieum_app/features/history/presentation/cubit/recent_requests_cubit.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';

class RecentRequestsSection extends StatelessWidget {
  const RecentRequestsSection({super.key});
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = RecentRequestsCubit(context.read<HistoryRepository>());
      unawaited(cubit.load());
      return cubit;
    },
    child: BlocBuilder<RecentRequestsCubit, RecentRequestsState>(
      builder: (context, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 14, 12, 4),
            child: Text(
              '최근 요청',
              style: TextStyle(fontSize: 12, color: AppTokens.ink3),
            ),
          ),
          if (state.loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            )
          else if (state.failure != null)
            TextButton(
              onPressed: () =>
                  unawaited(context.read<RecentRequestsCubit>().load()),
              child: const Text('최근 요청 다시 불러오기'),
            )
          else if (state.entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('최근 요청이 없어요', style: AppTokens.copy),
            )
          else
            for (final entry in state.entries)
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: Text(
                  entry.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.volume_up_outlined),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(
                    context.push<void>(
                      '/speak/playback',
                      extra: PlaybackRequest(
                        text: entry.text,
                        origin: PlaybackOrigin.history,
                      ),
                    ),
                  );
                },
              ),
        ],
      ),
    ),
  );
}
