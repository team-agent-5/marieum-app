import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:marieum_app/features/auth/presentation/bloc/auth_bloc.dart';

class AuthRouterRefresh extends ChangeNotifier {
  AuthRouterRefresh(AuthBloc bloc) {
    _subscription = bloc.stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<AuthState> _subscription;
  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
