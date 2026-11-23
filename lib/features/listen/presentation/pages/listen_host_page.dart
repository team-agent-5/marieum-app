import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/router/app_routes.dart';
import 'package:marieum_app/features/listen/presentation/cubit/listen_host_cubit.dart';
import 'package:marieum_app/features/listen/presentation/widgets/listen_host_view.dart';
import 'package:marieum_app/features/listen/presentation/widgets/listen_route_exit.dart';

class ListenHostPage extends StatelessWidget {
  const ListenHostPage({required this.createCubit, super.key});

  final ListenHostCubit Function() createCubit;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = createCubit();
      unawaited(cubit.start());
      return cubit;
    },
    child: Builder(
      builder: (context) {
        final cubit = context.read<ListenHostCubit>();
        return ListenRouteExit(
          cleanup: cubit.end,
          fallback: AppRoutes.speak,
          onBack: () {
            if (cubit.state.phase != ListenHostPhase.connected) return false;
            if (ModalRoute.of(context)?.isCurrent != true) return true;
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop<bool>(true);
            } else {
              context.go(AppRoutes.live);
            }
            return true;
          },
          builder: (onBack, onClose) =>
              ListenHostView(onClose: onClose, onBack: onBack),
        );
      },
    ),
  );
}
