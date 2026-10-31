import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/presentation/cubit/playback_cubit.dart';
import 'package:marieum_app/features/speak/presentation/widgets/playback_view.dart';

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
      child: const PlaybackView(),
    ),
  );
}
