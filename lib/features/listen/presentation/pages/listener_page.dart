import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/app/router/app_routes.dart';
import 'package:marieum_app/features/listen/presentation/cubit/listener_cubit.dart';
import 'package:marieum_app/features/listen/presentation/widgets/listen_route_exit.dart';
import 'package:marieum_app/features/listen/presentation/widgets/listener_view.dart';

class ListenerPage extends StatelessWidget {
  const ListenerPage({required this.createCubit, super.key});

  final ListenerCubit Function() createCubit;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => createCubit(),
    child: Builder(
      builder: (context) => ListenRouteExit(
        cleanup: context.read<ListenerCubit>().leave,
        fallback: AppRoutes.login,
        builder: (_, onClose) => ListenerView(onClose: onClose),
      ),
    ),
  );
}
