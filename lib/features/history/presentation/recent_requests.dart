import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/key_text.dart';
import 'package:marieum_app/features/history/domain/history.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';

class RecentRequestsState extends Equatable {
  const RecentRequestsState({
    this.entries = const [],
    this.loading = false,
    this.failure,
  });
  final List<HistoryEntry> entries;
  final bool loading;
  final Failure? failure;
  @override
  List<Object?> get props => [entries, loading, failure];
}

class RecentRequestsCubit extends Cubit<RecentRequestsState> {
  RecentRequestsCubit(this._repository) : super(const RecentRequestsState());
  final HistoryRepository _repository;
  Future<void> load() async {
    if (state.loading) return;
    emit(const RecentRequestsState(loading: true));
    final result = await _repository.recent();
    if (isClosed) return;
    emit(switch (result) {
      Success(:final value) => RecentRequestsState(entries: value),
      FailureResult(:final failure) => RecentRequestsState(failure: failure),
    });
  }
}

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
                title: KeyText(entry.text),
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
