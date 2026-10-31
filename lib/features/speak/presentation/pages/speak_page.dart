import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/features/speak/presentation/cubit/speak_mode_cubit.dart';
import 'package:marieum_app/features/speak/presentation/widgets/speak_view.dart';

class SpeakPage extends StatelessWidget {
  const SpeakPage({super.key});
  @override
  Widget build(BuildContext context) =>
      BlocListener<SpeakModeCubit, SpeakModeState>(
        listenWhen: (previous, current) =>
            current.failure != null && previous.failure != current.failure,
        listener: (context, state) => ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.failure!.message))),
        child: const SpeakView(),
      );
}
