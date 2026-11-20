import 'dart:async';
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
