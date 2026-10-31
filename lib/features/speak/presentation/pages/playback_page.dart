import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/presentation/cubit/playback_cubit.dart';
import 'package:marieum_app/features/speak/presentation/widgets/playback_view.dart';
import 'package:marieum_app/features/speak/presentation/widgets/proactive_suggestion_dialog.dart';

class PlaybackPage extends StatelessWidget {
  const PlaybackPage({
    required this.request,
    required this.createCubit,
    super.key,
  });
  final PlaybackRequest request;
  final PlaybackCubit Function(PlaybackRequest) createCubit;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = createCubit(request);
      unawaited(cubit.start());
      return cubit;
    },
    child: BlocListener<PlaybackCubit, PlaybackState>(
      listenWhen: (previous, current) =>
          current.status == PlaybackStatus.closed &&
          previous.status != current.status,
      listener: (context, state) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/speak');
        }
      },
      child: BlocBuilder<PlaybackCubit, PlaybackState>(
        builder: (context, state) => PopScope(
          canPop: !state.suggestionPending,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) context.read<PlaybackCubit>().declineSuggestion();
          },
          child: Stack(
            children: [
              const PlaybackView(),
              if (state.suggestionPending && state.suggestion != null)
                Positioned.fill(
                  child: ProactiveSuggestionDialog(
                    suggestion: state.suggestion!,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
