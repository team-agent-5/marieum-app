import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:marieum_app/features/auth/presentation/cubit/auth_form_state.dart';
import 'package:marieum_app/features/auth/presentation/cubit/login_cubit.dart';
import 'package:marieum_app/features/auth/presentation/widgets/auth_form_view.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({required this.repository, super.key});
  final AuthRepository repository;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => LoginCubit(repository),
    child: const LoginView(),
  );
}

class LoginView extends StatelessWidget {
  const LoginView({super.key});
  @override
  Widget build(BuildContext context) => BlocBuilder<LoginCubit, AuthFormState>(
    builder: (context, state) => AuthFormView(
      state: state,
      onSubmit: (input) async {
        await context.read<LoginCubit>().submit(
          userId: input.userId,
          password: input.password,
        );
      },
    ),
  );
}
