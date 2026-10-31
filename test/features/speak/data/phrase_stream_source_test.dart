import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/network/session_expiry_signal.dart';
import 'package:marieum_app/core/storage/secure_token_store.dart';
import 'package:marieum_app/features/speak/data/datasources/phrase_stream_source.dart';
import 'package:marieum_app/features/speak/domain/repositories/live_stream.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _MockTokens extends Mock implements SecureTokenStore {}

class _FakeSink extends Fake implements WebSocketSink {
  final sent = <Object?>[];
  bool closed = false;

  @override
  void add(Object? data) => sent.add(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async =>
      closed = true;
}

class _FakeChannel extends Fake implements WebSocketChannel {
  _FakeChannel({this.fails = false});

  final bool fails;
  final incoming = StreamController<Object?>();
  @override
  final _FakeSink sink = _FakeSink();
  @override
  int? closeCode;

  @override
  Future<void> get ready =>
      fails ? Future.error(WebSocketChannelException('down')) : Future.value();

  @override
  Stream<Object?> get stream => incoming.stream;

  void send(Map<String, Object?> json) => incoming.add(jsonEncode(json));

  Future<void> closeWith(int code) async {
    closeCode = code;
    await incoming.close();
  }

  List<String> get texts => sink.sent.whereType<String>().toList();
  List<Uint8List> get frames => sink.sent.whereType<Uint8List>().toList();
}

void main() {
  late _MockTokens tokens;
  late SessionExpirySignal expiry;
  late List<Uri> uris;
  late List<_FakeChannel> channels;
  late List<_FakeChannel> queued;

  setUp(() {
    tokens = _MockTokens();
    expiry = SessionExpirySignal();
    uris = [];
    channels = [];
    queued = [];
    when(tokens.read).thenAnswer((_) async => 'jwt');
  });

  PhraseStreamSource source() => PhraseStreamSource(
    endpoint: PhraseStreamSource.endpointFor('https://api.test'),
    tokens: tokens,
    expiry: expiry,
    retryDelays: const [Duration.zero, Duration.zero],
    connect: (uri) {
      uris.add(uri);
      final channel = queued.isEmpty ? _FakeChannel() : queued.removeAt(0);
      channels.add(channel);
      return channel;
    },
  );

  group(PhraseStreamSource, () {
    test('derives the stream address from the API address', () {
      expect(
        PhraseStreamSource.endpointFor('https://api.test').toString(),
        'wss://api.test/ws/phrase/stream',
      );
      expect(
        PhraseStreamSource.endpointFor('http://10.0.2.2:8000').toString(),
        'ws://10.0.2.2:8000/ws/phrase/stream',
      );
    });

    test(
      'streams 100 ms frames, ends, and reports interim and final',
      () async {
        final utterance = source().open()..add(Uint8List(8000));
        final events = <LiveEvent>[];
        utterance.events.listen(events.add);
        await pumpEventQueue();
        final channel = channels.single;
        expect(uris.single.queryParameters['token'], 'jwt');
        expect(uris.single.path, '/ws/phrase/stream');
        expect(channel.frames.map((f) => f.length), [3200, 3200]);

        channel.send({
          'type': 'transcript',
          'text': '물 좀',
          'final': false,
          'trace_id': 'a1',
          'confidence': null,
        });
        utterance.end();
        await pumpEventQueue();
        expect(channel.frames.last.length, 1600);
        expect(channel.texts.single, '{"type":"end"}');

        channel.send({
          'type': 'transcript',
          'text': '물 좀 주세요',
          'final': true,
          'trace_id': 'a1',
          'confidence': 0.82,
        });
        await pumpEventQueue();
        expect((events.first as LiveInterim).text, '물 좀');
        final transcription = (events.last as LiveFinal).transcription;
        expect(transcription.finalTranscript, '물 좀 주세요');
        expect(transcription.asrConfidence, 0.82);
        expect(transcription.traceId, 'a1');
        expect(channel.sink.closed, isTrue);
      },
    );

    test('reports unclear speech', () async {
      final utterance = source().open();
      final events = utterance.events.toList();
      await pumpEventQueue();
      channels.single.send({
        'type': 'error',
        'error_code': 'ASR_LOW_CONFIDENCE',
        'message': '말소리를 인식하지 못했어요.',
        'trace_id': 'a1',
      });
      expect(await events, [isA<LiveUnclear>()]);
    });

    test('reconnects when the recognizer is down and replays audio', () async {
      final utterance = source().open()..add(Uint8List(3200));
      final events = utterance.events.toList();
      await pumpEventQueue();
      utterance.end();
      await channels.first.closeWith(4503);
      await pumpEventQueue();
      expect(channels, hasLength(2));
      expect(channels.last.frames, hasLength(1));
      expect(channels.last.texts.single, '{"type":"end"}');
      channels.last.send({
        'type': 'transcript',
        'text': '네',
        'final': true,
        'trace_id': 'a2',
        'confidence': 0.9,
      });
      expect(await events, [isA<LiveFinal>()]);
    });

    test('gives up after the retries run out', () async {
      queued.addAll([
        for (var i = 0; i < 3; i++) _FakeChannel(fails: true),
      ]);
      final events = source().open().events.toList();
      final result = await events;
      expect(channels, hasLength(3));
      expect((result.single as LiveFailed).failure, isA<NetworkFailure>());
    });

    test('signals an expired session on 4001', () async {
      var expired = false;
      expiry.expired.listen((_) => expired = true);
      final events = source().open().events.toList();
      await pumpEventQueue();
      await channels.single.closeWith(4001);
      final result = await events;
      expect((result.single as LiveFailed).failure, isA<UnauthorizedFailure>());
      expect(expired, isTrue);
    });

    test('cancel tells the server and ends without a result', () async {
      final utterance = source().open();
      final events = utterance.events.toList();
      await pumpEventQueue();
      utterance.cancel();
      expect(await events, isEmpty);
      expect(channels.single.texts.single, '{"type":"cancel"}');
    });
  });
}
