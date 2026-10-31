import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/features/history/presentation/cubit/history_cubit.dart';
import 'package:marieum_app/features/history/presentation/widgets/history_view.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({required this.createCubit, super.key});
  final HistoryCubit Function() createCubit;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = createCubit();
      unawaited(cubit.load());
      return cubit;
    },
    child: const HistoryView(),
  );
}
