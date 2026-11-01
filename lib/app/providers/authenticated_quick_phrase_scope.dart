import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:marieum_app/features/quick_phrase/presentation/bloc/quick_phrase_bloc.dart';

class AuthenticatedQuickPhraseScope extends StatelessWidget {
  const AuthenticatedQuickPhraseScope({
    required this.createBloc,
    required this.child,
    super.key,
  });
  final QuickPhraseBloc Function() createBloc;
  final Widget child;
  @override
  Widget build(BuildContext context) => BlocBuilder<AuthBloc, AuthState>(
    buildWhen: (previous, current) =>
        _profileId(previous) != _profileId(current),
    builder: (context, auth) {
      final id = _profileId(auth);
      if (id == null) return const SizedBox.shrink();
      return BlocProvider(
        key: ValueKey(id),
        create: (_) => createBloc(),
        child: BlocListener<QuickPhraseBloc, QuickPhraseState>(
          listenWhen: (previous, current) =>
              current.status == QuickPhraseStatus.failure &&
              previous.status != current.status,
          listener: (context, state) => ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.failure!.message))),
          child: child,
        ),
      );
    },
  );

  static String? _profileId(AuthState state) => switch (state.status) {
    AuthAuthenticated(:final profile) => profile.id,
    _ => null,
  };
}
