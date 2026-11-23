import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';
import 'package:marieum_app/features/listen/domain/repositories/listen_repository.dart';
import 'package:marieum_app/features/listen/domain/repositories/listener_channel.dart';
import 'package:marieum_app/features/listen/presentation/cubit/listener_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements ListenJoinRepository {}

class _FakeConnection implements ListenerConnection {
  final controller = StreamController<ListenerEvent>();
  final playedIds = <String>[];
  bool closed = false;

  @override
  Stream<ListenerEvent> get events => controller.stream;
  @override
  void played(String utteranceId) => playedIds.add(utteranceId);
  @override
  Future<void> close() async => closed = true;
}

class _FakeChannel implements ListenerChannel {
  final connections = <_FakeConnection>[];
  _FakeConnection get connection => connections.last;
  ListenerPass? pass;
  @override
  ListenerConnection connect(ListenerPass pass) {
    this.pass = pass;
    final connection = _FakeConnection();
    connections.add(connection);
    return connection;
  }
}

class _FakeTts implements PlaybackTtsPort {
  final spoken = <String>[];
  final pending = <Completer<Result<void>>>[];
  bool stopped = false;

  /// Whether playback starts; false for an engine that fails at once.
  bool starts = true;

  @override
  Future<Result<void>> speakWithPlayback(
    String text, {
    required void Function() onStarted,
    required void Function() onEnded,
  }) {
    spoken.add(text);
    if (starts) onStarted();
    final done = Completer<Result<void>>();
    pending.add(done);
    return done.future;
  }

  @override
  Future<bool> isKoreanAvailable() async => true;
  @override
  Future<Result<void>> speak(String text) async => const Success(null);
  @override
  Future<Result<void>> stop() async {
    stopped = true;
    return const Success(null);
  }
}

void main() {
  group(ListenerCubit, () {
    late _MockRepository repository;
    late _FakeChannel channel;
    late _FakeTts tts;
    final pass = ListenerPass(token: 'tok', expiresAt: DateTime(2030));

    setUp(() {
      repository = _MockRepository();
      channel = _FakeChannel();
      tts = _FakeTts();
      when(
        () => repository.join(any()),
      ).thenAnswer((_) async => Success(pass));
    });

    ListenerCubit build() =>
        ListenerCubit(repository: repository, channel: channel, tts: tts);

    test('refuses a malformed code without asking the server', () async {
      final cubit = build();
      await cubit.join('K7Q');
      expect(cubit.state.phase, ListenerPhase.entering);
      expect(cubit.state.error, isNotNull);
      verifyNever(() => repository.join(any()));
      await cubit.close();
    });

    test('refuses a QR that is not a Marieum code', () async {
      final cubit = build();
      await cubit.joinScanned('https://example.com');
      expect(cubit.state.error, isNotNull);
      verifyNever(() => repository.join(any()));
      await cubit.close();
    });

    test('joins with the normalized code and connects with the pass', () async {
      final cubit = build();
      await cubit.join('k7q 2mx');
      verify(() => repository.join('K7Q2MX')).called(1);
      expect(channel.pass, pass);
      expect(cubit.state.phase, ListenerPhase.connecting);
      channel.connection.controller.add(const ListenerConnected());
      await pumpEventQueue();
      expect(cubit.state.phase, ListenerPhase.listening);
      await cubit.close();
    });

    for (final (code, text) in [
      ('LISTEN_CODE_INVALID', '코드가 맞지 않거나 시간이 지났어요.'),
      ('LISTENER_ALREADY_JOINED', '이미 다른 폰이 연결되어 있어요.'),
      ('RATE_LIMITED', '잠시 뒤에 다시 시도해 주세요.'),
    ]) {
      test('$code is explained', () async {
        when(() => repository.join(any())).thenAnswer(
          (_) async => FailureResult(
            ServerFailure(statusCode: 404, errorCode: code),
          ),
        );
        final cubit = build();
        await cubit.join('K7Q2MX');
        expect(cubit.state.phase, ListenerPhase.entering);
        expect(cubit.state.error, text);
        await cubit.close();
      });
    }

    test(
      'says sentences in order, once each, and reports them played',
      () async {
        final cubit = build();
        await cubit.join('K7Q2MX');
        channel.connection.controller
          ..add(const ListenerConnected())
          ..add(const ListenerSay(utteranceId: 'u1', text: '물 주세요'))
          ..add(const ListenerSay(utteranceId: 'u2', text: '고마워요'))
          ..add(const ListenerSay(utteranceId: 'u1', text: '물 주세요'));
        await pumpEventQueue();
        expect(cubit.state.lines.map((line) => line.utteranceId), ['u1', 'u2']);
        expect(tts.spoken, ['물 주세요']);
        expect(cubit.state.speakingId, 'u1');
        // Reported as soon as it starts, as the server relays it.
        expect(channel.connection.playedIds, ['u1']);

        tts.pending.removeAt(0).complete(const Success(null));
        await pumpEventQueue();
        expect(tts.spoken, ['물 주세요', '고마워요']);
        expect(channel.connection.playedIds, ['u1', 'u2']);

        tts.pending.removeAt(0).complete(const Success(null));
        await pumpEventQueue();
        expect(cubit.state.speakingId, isNull);
        await cubit.close();
      },
    );

    test('shows reconnecting and the end of the session', () async {
      final cubit = build();
      await cubit.join('K7Q2MX');
      channel.connection.controller.add(const ListenerReconnecting());
      await pumpEventQueue();
      expect(cubit.state.phase, ListenerPhase.reconnecting);
      channel.connection.controller.add(
        const ListenerEnded(ListenEndReason.patientLeft),
      );
      await pumpEventQueue();
      expect(cubit.state.phase, ListenerPhase.ended);
      expect(cubit.state.endReason, ListenEndReason.patientLeft);
      expect(channel.connection.closed, isTrue);
      await cubit.close();
    });

    test('can join again after the session ended', () async {
      final cubit = build();
      await cubit.join('K7Q2MX');
      channel.connection.controller.add(
        const ListenerEnded(ListenEndReason.revoked),
      );
      await pumpEventQueue();
      await cubit.join('ABCDEF');
      expect(cubit.state.phase, ListenerPhase.connecting);
      expect(cubit.state.endReason, isNull);
      expect(channel.connections, hasLength(2));
      await cubit.close();
    });

    test('a join answered after leaving opens no connection', () async {
      final joined = Completer<Result<ListenerPass>>();
      when(() => repository.join(any())).thenAnswer((_) => joined.future);
      final cubit = build();
      final joining = cubit.join('K7Q2MX');
      await cubit.leave();
      joined.complete(Success(pass));
      await joining;
      expect(channel.connections, isEmpty);
      await cubit.close();
    });

    test('a line that never starts is not reported as played', () async {
      tts.starts = false;
      final cubit = build();
      await cubit.join('K7Q2MX');
      channel.connection.controller
        ..add(const ListenerConnected())
        ..add(const ListenerSay(utteranceId: 'u1', text: '물 주세요'));
      await pumpEventQueue();
      tts.pending.single.complete(const FailureResult(TtsFailure('x')));
      await pumpEventQueue();
      expect(channel.connection.playedIds, isEmpty);
      await cubit.close();
    });

    test('a line finished after the session ended is not reported on the '
        'next session', () async {
      final cubit = build();
      await cubit.join('K7Q2MX');
      final first = channel.connection;
      first.controller
        ..add(const ListenerConnected())
        ..add(const ListenerSay(utteranceId: 'u1', text: '물 주세요'))
        ..add(const ListenerEnded(ListenEndReason.patientLeft));
      await pumpEventQueue();
      await cubit.join('ABCDEF');
      tts.pending.single.complete(const Success(null));
      await pumpEventQueue();
      // Only its start went out, on the connection it came on.
      expect(first.playedIds, ['u1']);
      expect(channel.connection.playedIds, isEmpty);
      await cubit.close();
    });

    test('leave stops speech and closes the connection', () async {
      final cubit = build();
      await cubit.join('K7Q2MX');
      await cubit.leave();
      expect(tts.stopped, isTrue);
      expect(channel.connection.closed, isTrue);
      await cubit.close();
    });
  });
}
