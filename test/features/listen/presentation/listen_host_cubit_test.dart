import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';
import 'package:marieum_app/features/listen/domain/repositories/listen_repository.dart';
import 'package:marieum_app/features/listen/presentation/cubit/listen_host_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements ListenHostRepository {}

void main() {
  group(ListenHostCubit, () {
    late _MockRepository repository;
    final start = DateTime(2026, 11, 22, 10);
    ListenSession session(String code) => ListenSession(
      id: 'ls_$code',
      joinCode: code,
      joinExpiresAt: start.add(const Duration(minutes: 10)),
      expiresAt: start.add(const Duration(hours: 2)),
    );

    setUp(() {
      repository = _MockRepository();
      when(
        () => repository.create(),
      ).thenAnswer((_) async => Success(session('K7Q2MX')));
      when(
        () => repository.current(),
      ).thenAnswer(
        (_) async =>
            const Success(ListenSnapshot(status: ListenStatus.waiting)),
      );
      when(
        () => repository.end(),
      ).thenAnswer((_) async => const Success(null));
    });

    test('shows the code and counts the join time down', () {
      fakeAsync((async) {
        final cubit = ListenHostCubit(
          repository: repository,
          now: () => start.add(async.elapsed),
        );
        unawaited(cubit.start());
        async.flushMicrotasks();
        expect(cubit.state.phase, ListenHostPhase.waiting);
        expect(cubit.state.session?.joinCode, 'K7Q2MX');
        expect(cubit.state.joinRemaining, const Duration(minutes: 10));
        async.elapse(const Duration(seconds: 3));
        expect(
          cubit.state.joinRemaining,
          const Duration(minutes: 9, seconds: 57),
        );
        unawaited(cubit.close());
      });
    });

    test('follows the status to connected and back to a new code', () {
      fakeAsync((async) {
        final cubit = ListenHostCubit(
          repository: repository,
          now: () => start.add(async.elapsed),
        );
        unawaited(cubit.start());
        async.flushMicrotasks();
        when(
          () => repository.current(),
        ).thenAnswer(
          (_) async =>
              const Success(ListenSnapshot(status: ListenStatus.connected)),
        );
        async.elapse(const Duration(seconds: 2));
        expect(cubit.state.phase, ListenHostPhase.connected);

        when(
          () => repository.current(),
        ).thenAnswer(
          (_) async =>
              const Success(ListenSnapshot(status: ListenStatus.waiting)),
        );
        async.elapse(const Duration(seconds: 2));
        expect(cubit.state.phase, ListenHostPhase.left);

        when(
          () => repository.create(),
        ).thenAnswer((_) async => Success(session('ABCDEF')));
        unawaited(cubit.renew());
        async.flushMicrotasks();
        expect(cubit.state.phase, ListenHostPhase.waiting);
        expect(cubit.state.session?.joinCode, 'ABCDEF');
        unawaited(cubit.close());
      });
    });

    test('the code runs out when nobody joined', () {
      fakeAsync((async) {
        final cubit = ListenHostCubit(
          repository: repository,
          now: () => start.add(async.elapsed),
          pollEvery: const Duration(minutes: 30),
        );
        unawaited(cubit.start());
        async
          ..flushMicrotasks()
          ..elapse(const Duration(minutes: 10, seconds: 1));
        expect(cubit.state.phase, ListenHostPhase.codeExpired);
        unawaited(cubit.close());
      });
    });

    test('an ended status from the server ends it', () {
      fakeAsync((async) {
        final cubit = ListenHostCubit(
          repository: repository,
          now: () => start.add(async.elapsed),
        );
        unawaited(cubit.start());
        async.flushMicrotasks();
        when(
          () => repository.current(),
        ).thenAnswer(
          (_) async =>
              const Success(ListenSnapshot(status: ListenStatus.ended)),
        );
        async.elapse(const Duration(seconds: 2));
        expect(cubit.state.phase, ListenHostPhase.ended);
        unawaited(cubit.close());
      });
    });

    test('a failed create can be tried again', () async {
      when(
        () => repository.create(),
      ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
      final cubit = ListenHostCubit(repository: repository);
      await cubit.start();
      expect(cubit.state.phase, ListenHostPhase.failed);
      expect(cubit.state.failure, isA<NetworkFailure>());
      await cubit.close();
    });

    test('ending while the session is still opening waits for it and '
        'ends it with one DELETE', () async {
      final created = Completer<Result<ListenSession>>();
      when(() => repository.create()).thenAnswer((_) => created.future);
      final cubit = ListenHostCubit(repository: repository);
      unawaited(cubit.start());
      await pumpEventQueue();
      var ended = false;
      final ending = cubit.end().then((_) => ended = true);
      await pumpEventQueue();
      expect(ended, isFalse);
      verifyNever(() => repository.end());
      created.complete(Success(session('K7Q2MX')));
      await ending;
      verify(() => repository.end()).called(1);
      expect(cubit.state.phase, ListenHostPhase.ended);
      await cubit.close();
    });

    test('ending while a failed open is under way sends no DELETE', () async {
      final created = Completer<Result<ListenSession>>();
      when(() => repository.create()).thenAnswer((_) => created.future);
      final cubit = ListenHostCubit(repository: repository);
      unawaited(cubit.start());
      await pumpEventQueue();
      final ending = cubit.end();
      created.complete(const FailureResult(NetworkFailure()));
      await ending;
      verifyNever(() => repository.end());
      await cubit.close();
    });

    test('renewing again while a code is being made sends one POST', () async {
      final created = Completer<Result<ListenSession>>();
      when(() => repository.create()).thenAnswer((_) => created.future);
      final cubit = ListenHostCubit(repository: repository);
      unawaited(cubit.renew());
      unawaited(cubit.renew());
      created.complete(Success(session('K7Q2MX')));
      await pumpEventQueue();
      verify(() => repository.create()).called(1);
      expect(cubit.state.phase, ListenHostPhase.waiting);
      await cubit.close();
    });

    test('picks up a session still waiting with its code', () async {
      when(() => repository.current()).thenAnswer(
        (_) async => Success(
          ListenSnapshot(
            status: ListenStatus.waiting,
            id: 'ls_old',
            joinCode: 'ABCDEF',
            joinExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        ),
      );
      final cubit = ListenHostCubit(repository: repository);
      await cubit.start();
      expect(cubit.state.phase, ListenHostPhase.waiting);
      expect(cubit.state.session?.joinCode, 'ABCDEF');
      verifyNever(() => repository.create());
      await cubit.close();
    });

    test('picks up a session the other phone is still listening to', () async {
      when(() => repository.current()).thenAnswer(
        (_) async => const Success(
          ListenSnapshot(status: ListenStatus.connected, id: 'ls_old'),
        ),
      );
      final cubit = ListenHostCubit(repository: repository);
      await cubit.start();
      expect(cubit.state.phase, ListenHostPhase.connected);
      verifyNever(() => repository.create());
      await cubit.close();
    });

    test(
      'opens a new one when the old code is used up or there is none',
      () async {
        when(() => repository.current()).thenAnswer(
          (_) async => const Success(
            ListenSnapshot(status: ListenStatus.waiting, id: 'ls_old'),
          ),
        );
        final cubit = ListenHostCubit(repository: repository);
        await cubit.start();
        expect(cubit.state.session?.joinCode, 'K7Q2MX');
        verify(() => repository.create()).called(1);
        await cubit.close();
      },
    );

    test('does not replace a session it could not read', () async {
      when(
        () => repository.current(),
      ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
      final cubit = ListenHostCubit(repository: repository);
      await cubit.start();
      expect(cubit.state.phase, ListenHostPhase.failed);
      verifyNever(() => repository.create());

      // Trying again reads it first.
      when(() => repository.current()).thenAnswer(
        (_) async => const Success(
          ListenSnapshot(status: ListenStatus.connected, id: 'ls_old'),
        ),
      );
      await cubit.renew();
      expect(cubit.state.phase, ListenHostPhase.connected);
      verifyNever(() => repository.create());
      await cubit.close();
    });

    test('end tells the server once and stops following', () async {
      final cubit = ListenHostCubit(repository: repository);
      await cubit.start();
      await cubit.end();
      await cubit.end();
      expect(cubit.state.phase, ListenHostPhase.ended);
      verify(() => repository.end()).called(1);
      await cubit.close();
    });
  });
}
