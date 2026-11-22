import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/network/session_expiry_signal.dart';
import 'package:marieum_app/core/storage/secure_token_store.dart';
import 'package:marieum_app/features/speak/data/datasources/phrase_stream_source.dart';
import 'package:marieum_app/features/speak/domain/repositories/live_stream.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _MockTokens extends Mock implements SecureTokenStore {}

class _FakeSink extends Fake implements WebSocketSink {
  final sent = <Object?>[];
  @override
  void add(Object? data) => sent.add(data);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
}

class _FakeChannel extends Fake implements WebSocketChannel {
  final _ready = Completer<void>();
  final _incoming = StreamController<Object?>();
  final _sink = _FakeSink();
  int? _closeCode;

  List<Object?> get sent => _sink.sent;

  void open() => _ready.complete();

  /// The server closes an open connection.
  void hangUp() => unawaited(_incoming.close());

  /// A message from the server.
  void receive(String message) => _incoming.add(message);

  /// Opens and is closed by the server right away with [code].
  void refuse(int code) {
    _closeCode = code;
    open();
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

void main() {
  group(PhraseStreamSource, () {
    late _MockTokens tokens;
    late List<LiveEvent> events;

    setUp(() {
      tokens = _MockTokens();
      when(tokens.read).thenAnswer((_) async => 'token');
      events = [];
    });

    LiveConversation connect(
      WebSocketChannel Function() channel, {
      List<Duration> retryDelays = const [Duration(seconds: 1)],
    }) {
      final conversation = PhraseStreamSource(
        endpoint: Uri.parse('wss://example.com/ws/phrase/stream'),
        tokens: tokens,
        expiry: SessionExpirySignal(),
        connect: (_) => channel(),
        retryDelays: retryDelays,
      ).connect();
      conversation.events.listen(events.add);
      return conversation;
    }

    test('reads the end of the session and a pace warning', () async {
      final channel = _FakeChannel()..open();
      final conversation = connect(() => channel);
      await Future<void>.delayed(Duration.zero);
      // As the server sent them after `end` on 2026-11-20.
      channel
        ..receive(
          '{"type":"transcript","text":"물 좀 주세요","final":true, '
          '"is_last":false,"trace_id":"t","confidence":0.5602}',
        )
        ..receive('{"type":"error","error_code":"RATE_LIMITED","trace_id":"t"}')
        ..receive('{"type":"ping","trace_id":"t"}')
        ..receive('{"type":"session_end","trace_id":"t"}');
      await Future<void>.delayed(Duration.zero);

      expect(events, [isA<LiveFinal>(), isA<LiveSessionEnded>()]);
      await conversation.close();
    });

    test('sends say and reads said, played and listener', () async {
      final channel = _FakeChannel();
      final conversation = connect(() => channel);
      // Nothing goes out before the connection opens.
      expect(
        conversation.say(utteranceId: 'u0', text: '물', traceId: 't'),
        isFalse,
      );
      channel.open();
      await Future<void>.delayed(Duration.zero);
      expect(
        conversation.say(utteranceId: 'u1', text: '물 주세요', traceId: 't'),
        isTrue,
      );
      final say = jsonDecode(channel.sent.single! as String) as Map;
      expect(say['type'], 'say');
      expect(say['utterance_id'], 'u1');
      expect(say['text'], '물 주세요');
      expect(say['trace_id'], 't');
      expect(DateTime.parse(say['client_ts'] as String).isUtc, isTrue);

      channel
        ..receive('{"type":"listener","state":"joined"}')
        ..receive('{"type":"said","utterance_id":"u1","delivered":true}')
        ..receive('{"type":"played","utterance_id":"u1"}')
        ..receive('{"type":"listener","state":"left"}')
        ..receive('{"type":"listener","state":"odd"}');
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(4));
      expect((events[0] as LiveListener).presence, ListenerPresence.joined);
      expect((events[1] as LiveSaid).delivered, isTrue);
      expect((events[2] as LivePlayed).utteranceId, 'u1');
      expect((events[3] as LiveListener).presence, ListenerPresence.left);
      await conversation.close();
    });

    test('ends the input after the audio already given', () async {
      final channels = <_FakeChannel>[];
      final conversation = connect(() {
        final channel = _FakeChannel()..open();
        channels.add(channel);
        return channel;
      });
      await Future<void>.delayed(Duration.zero);
      conversation
        ..add(Uint8List(3200))
        ..add(Uint8List(1000))
        ..end()
        ..add(Uint8List(3200));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final sent = channels.single.sent;
      expect(sent.whereType<Uint8List>().map((f) => f.length), [3200, 1000]);
      expect(sent.last, '{"type":"end"}');

      // Nothing more comes after `end`, so a closed connection stays closed.
      channels.single.hangUp();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(channels, hasLength(1));
      await conversation.close();
    });

    test('sends audio kept before opening under the server limit', () async {
      final channel = _FakeChannel();
      final conversation = connect(() => channel);
      for (var i = 0; i < 30; i++) {
        conversation.add(Uint8List(3200));
      }
      channel.open();
      await Future<void>.delayed(const Duration(seconds: 1));
      final bytes = channel.sent.whereType<Uint8List>().fold(
        0,
        (sum, frame) => sum + frame.length,
      );
      expect(bytes, inInclusiveRange(32000, 48000));
      await conversation.close();
    });

    test(
      'waits before reconnecting when a second connection is refused',
      () async {
        final channels = <_FakeChannel>[];
        final conversation = connect(() {
          final channel = _FakeChannel();
          // Stops an immediate reconnect loop from starving the test.
          if (channels.length < 50) channel.refuse(4003);
          channels.add(channel);
          return channel;
        }, retryDelays: const [Duration(milliseconds: 300)]);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(channels, hasLength(1));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(channels, hasLength(2));
        expect(events.whereType<LiveFailed>().first.recovering, isTrue);
        await conversation.close();
      },
    );
  });
}
