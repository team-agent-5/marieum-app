import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/domain/repositories/auth_repository.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

final class AuthSubscriptionRequested extends AuthEvent {
  const AuthSubscriptionRequested();
}

final class LogoutRequested extends AuthEvent {
  const LogoutRequested();
}

final class AuthState extends Equatable {
  const AuthState(this.status);
  final AuthStatus status;
  @override
  List<Object?> get props => [status];
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(AuthRepository repository)
    : super(AuthState(repository.currentStatus)) {
    on<AuthSubscriptionRequested>(
      (event, emit) => emit.forEach(repository.status, onData: AuthState.new),
      transformer: restartable(),
    );
    on<LogoutRequested>((event, emit) async {
      await repository.logout();
    }, transformer: droppable());
  }
}
