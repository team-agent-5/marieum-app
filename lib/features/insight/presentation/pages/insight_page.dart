import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/ui/feature_panel.dart';
import 'package:marieum_app/features/insight/presentation/cubit/insight_cubit.dart';
import 'package:marieum_app/features/insight/presentation/widgets/insight_view.dart';

class InsightPage extends StatelessWidget {
  const InsightPage({required this.createCubit, super.key});
  final InsightCubit Function() createCubit;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = createCubit();
      unawaited(cubit.load());
      return cubit;
    },
    child: const FeaturePage(title: '개인화 현황', child: InsightView()),
  );
}
