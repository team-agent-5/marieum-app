import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/features/speak/presentation/cubit/live_session_cubit.dart';
import 'package:marieum_app/features/speak/presentation/widgets/live_session_view.dart';

class LiveSessionPage extends StatelessWidget {
  const LiveSessionPage({required this.createCubit, super.key});

  final LiveSessionCubit Function() createCubit;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = createCubit();
      unawaited(cubit.start());
      return cubit;
    },
    child: Builder(
      builder: (context) {
        void close() {
          unawaited(context.read<LiveSessionCubit>().stop());
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/speak');
          }
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) close();
          },
          child: LiveSessionView(onClose: close),
        );
      },
    ),
  );
}
