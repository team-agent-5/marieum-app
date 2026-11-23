import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/listen/data/listener_socket.dart';
import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';
import 'package:marieum_app/features/listen/domain/repositories/listener_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeSink extends Fake implements WebSocketSink {
  final sent = <Object?>[];
  bool closed = false;
  @override
  void add(Object? data) => sent.add(data);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
  }
}

class _FakeChannel extends Fake implements WebSocketChannel {
  final _ready = Completer<void>();
  final _incoming = StreamController<Object?>();
  final _sink = _FakeSink();
  int? _closeCode;

  List<Object?> get sent => _sink.sent;
  bool get closed => _sink.closed;

  void open() => _ready.complete();
  void fail() => _ready.completeError(const SocketExceptionStub());
  void receive(Map<String, Object?> json) => _incoming.add(jsonEncode(json));
  void hangUp([int? code]) {
    _closeCode = code;
    unawaited(_incoming.close());
  }

  @override
  Future<void> get ready => _ready.future;
  @override
  Stream<Object?> get stream => _incoming.stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  int? get closeCode => _closeCode;
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}

void main() {
  group(ListenerSocket, () {
    final pass = ListenerPass(
      token: 'tok',
      expiresAt: DateTime(2030),
    );

    test('endpointFor derives the listen socket from the API address', () {
      expect(
        ListenerSocket.endpointFor('https://api.beens.kr').toString(),
        'wss://api.beens.kr/ws/listen',
      );
      expect(
        ListenerSocket.endpointFor('http://10.0.2.2:8000').toString(),
        'ws://10.0.2.2:8000/ws/listen',
      );
    });

    test('authenticates with the subprotocol and token, then relays say '
        'and sends played', () async {
      final channel = _FakeChannel();
      Iterable<String>? protocols;
      final socket = ListenerSocket(
        endpoint: Uri.parse('wss://x/ws/listen'),
        connect: (_, given) {
          protocols = given;
          return channel;
        },
      );
      final connection = socket.connect(pass);
      final events = <ListenerEvent>[];
      connection.events.listen(events.add);
      channel.open();
      await pumpEventQueue();
      expect(protocols, ['marieum.listen.v1', 'tok']);
      expect(events.single, isA<ListenerConnected>());

      channel
        ..receive({'type': 'ping'})
        ..receive({
          'type': 'say',
          'utterance_id': 'u1',
          'text': ' 물 주세요 ',
          'server_ts': '2026-11-22T00:00:00Z',
        })
        ..receive({'type': 'say', 'utterance_id': 'u2', 'text': '  '});
      await pumpEventQueue();
      final say = events.whereType<ListenerSay>().single;
      expect(say.utteranceId, 'u1');
      expect(say.text, '물 주세요');

      connection.played('u1');
      expect(jsonDecode(channel.sent.single! as String), {
        'type': 'played',
        'utterance_id': 'u1',
      });
      await connection.close();
      expect(channel.closed, isTrue);
    });

    test('session_end ends with its reason and does not reconnect', () async {
      var connects = 0;
      final channel = _FakeChannel();
      final socket = ListenerSocket(
        endpoint: Uri.parse('wss://x/ws/listen'),
        connect: (_, _) {
          connects++;
          return channel;
        },
      );
      final events = <ListenerEvent>[];
      socket.connect(pass).events.listen(events.add);
      channel
        ..open()
        ..receive({'type': 'session_end', 'reason': 'patient_left'});
      await pumpEventQueue();
      expect(
        (events.last as ListenerEnded).reason,
        ListenEndReason.patientLeft,
      );
      expect(connects, 1);
      expect(channel.closed, isTrue);
    });

    for (final (code, reason) in [
      (4001, ListenEndReason.tokenInvalid),
      (4004, ListenEndReason.expired),
      (4009, ListenEndReason.otherDevice),
    ]) {
      test('close code $code ends with $reason', () async {
        final channel = _FakeChannel();
        final socket = ListenerSocket(
          endpoint: Uri.parse('wss://x/ws/listen'),
          connect: (_, _) => channel,
        );
        final events = <ListenerEvent>[];
        socket.connect(pass).events.listen(events.add);
        channel
          ..open()
          ..hangUp(code);
        await pumpEventQueue();
        expect((events.last as ListenerEnded).reason, reason);
      });
    }

    test('a drop reconnects with the same token', () {
      fakeAsync((async) {
        final channels = [_FakeChannel(), _FakeChannel()];
        var index = 0;
        final socket = ListenerSocket(
          endpoint: Uri.parse('wss://x/ws/listen'),
          connect: (_, _) => channels[index++],
          now: () => DateTime(2026).add(async.elapsed),
        );
        final events = <ListenerEvent>[];
        socket.connect(pass).events.listen(events.add);
        channels[0].open();
        async.elapse(const Duration(seconds: 5));
        channels[0].receive({'type': 'ping'});
        async.flushMicrotasks();
        channels[0].hangUp(1006);
        async.flushMicrotasks();
        expect(events.last, isA<ListenerReconnecting>());
        expect(index, 2);
        channels[1].open();
        async.flushMicrotasks();
        expect(events.last, isA<ListenerConnected>());
      });
    });

    test('a connection that goes silent is dropped and opened again', () {
      fakeAsync((async) {
        final channels = <_FakeChannel>[];
        final socket = ListenerSocket(
          endpoint: Uri.parse('wss://x/ws/listen'),
          connect: (_, _) {
            final channel = _FakeChannel()..open();
            channels.add(channel);
            return channel;
          },
          now: () => DateTime(2026).add(async.elapsed),
        );
        final events = <ListenerEvent>[];
        socket.connect(pass).events.listen(events.add);
        async.flushMicrotasks();
        channels[0].receive({'type': 'ping'});
        async.elapse(const Duration(seconds: 39));
        expect(channels, hasLength(1));
        async.elapse(const Duration(seconds: 2));
        expect(channels, hasLength(2));
        expect(channels[0].closed, isTrue);
        expect(events.whereType<ListenerReconnecting>(), isNotEmpty);
      });
    });

    test('a connection that never says anything ends as lost', () {
      fakeAsync((async) {
        final socket = ListenerSocket(
          endpoint: Uri.parse('wss://x/ws/listen'),
          connect: (_, _) => _FakeChannel()..open(),
          now: () => DateTime(2026).add(async.elapsed),
        );
        final events = <ListenerEvent>[];
        socket.connect(pass).events.listen(events.add);
        async.elapse(const Duration(seconds: 45));
        expect(
          (events.last as ListenerEnded).reason,
          ListenEndReason.connectionLost,
        );
      });
    });

    test('gives up once offline past the limit', () {
      fakeAsync((async) {
        var connects = 0;
        final socket = ListenerSocket(
          endpoint: Uri.parse('wss://x/ws/listen'),
          connect: (_, _) {
            connects++;
            return _FakeChannel()..fail();
          },
          retryDelays: const [Duration(seconds: 5)],
          offlineLimit: const Duration(seconds: 12),
          now: () => DateTime(2026).add(async.elapsed),
        );
        final events = <ListenerEvent>[];
        socket.connect(pass).events.listen(events.add);
        async.elapse(const Duration(seconds: 20));
        expect(
          (events.last as ListenerEnded).reason,
          ListenEndReason.connectionLost,
        );
        expect(connects, 4);
      });
    });
  });
}
