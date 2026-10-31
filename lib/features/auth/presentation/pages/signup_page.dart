import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/cubit/auth_form_state.dart';
import 'package:marieum_app/features/auth/presentation/cubit/signup_cubit.dart';
import 'package:marieum_app/features/auth/presentation/widgets/auth_form_view.dart';

class SignupPage extends StatelessWidget {
  const SignupPage({required this.repository, super.key});
  final AuthRepository repository;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SignupCubit(repository),
    child: const SignupView(),
  );
}

class SignupView extends StatelessWidget {
  const SignupView({super.key});
  @override
  Widget build(BuildContext context) => BlocBuilder<SignupCubit, AuthFormState>(
    builder: (context, state) => AuthFormView(
      state: state,
      signup: true,
      onSubmit: (input) async {
        await context.read<SignupCubit>().submit(
          userId: input.userId,
          password: input.password,
          passwordConfirm: input.passwordConfirm,
          nickname: input.nickname,
        );
      },
    ),
  );
}
