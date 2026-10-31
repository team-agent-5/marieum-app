import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/core/storage/sequence_store.dart';
import 'package:marieum_app/features/speak/data/datasources/selection_log_queue.dart';
import 'package:marieum_app/features/speak/data/datasources/utterance_data_source.dart';
import 'package:marieum_app/features/speak/data/dto/utterance_dto.dart';
import 'package:marieum_app/features/speak/data/repositories/utterance_repository_impl.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';
import 'package:mocktail/mocktail.dart';

class _MemoryPrefs implements PrefsBackend {
  final values = <String, Object>{};
  @override
  String? readString(String key) => values[key] as String?;
  @override
  bool? readBool(String key) => values[key] as bool?;
  @override
  Future<void> writeString(String key, String value) async =>
      values[key] = value;
  @override
  Future<void> writeBool(String key, {required bool value}) async =>
      values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
}

class _MockSource extends Mock implements UtteranceDataSource {}

const _transcription = Transcription(
  traceId: 't1',
  finalTranscript: '물 좀 주세요',
  asrConfidence: 0.82,
);

const _suggestions = Suggestions(
  traceId: 's1',
  candidates: [
    Candidate(
      rank: 1,
      text: '물 주세요',
      score: 0.9,
      reasonLabel: 'patient_frequency',
      reasonDisplay: '자주 쓰는 말',
      source: CandidateSource.patientLog,
    ),
    Candidate(rank: 2, text: '미지근한 물 주세요', score: 0.7),
  ],
);

void main() {
  late PrefsStore prefs;
  late SequenceStore sequence;
  late _MockSource source;
  final sent = <Map<String, Object?>>[];

  setUp(() {
    prefs = PrefsStore(_MemoryPrefs());
    sequence = SequenceStore(prefs);
    source = _MockSource();
    sent.clear();
    when(() => source.selection(any())).thenAnswer((invocation) async {
      sent.add(invocation.positionalArguments.single as Map<String, Object?>);
      return const Success('77');
    });
  });

  UtteranceRepositoryImpl repository() => UtteranceRepositoryImpl(
    source: source,
    sequence: sequence,
    queue: SelectionLogQueue(
      prefs: prefs,
      sequence: sequence,
      send: source.selection,
    ),
    now: () => DateTime(2026, 10, 31, 23, 5),
  );

  group(UtteranceDto, () {
    test('parses transcription with numeric strings and blank heard text', () {
      final value = UtteranceDto.transcription({
        'trace_id': 'abc',
        'final_transcript': '물',
        'asr_confidence': '0.35',
        'duration_ms': 1800,
        'heard_text': ' ',
      });
      expect(value.asrConfidence, 0.35);
      expect(value.heardText, isNull);
      expect(value.isLowConfidence, isTrue);
    });

    test('orders candidates by rank and keeps at most three', () {
      final value = UtteranceDto.suggestions({
        'trace_id': 'abc',
        'candidates': [
          for (final rank in [3, 1, 2, 4])
            {'rank': rank, 'text': '문장 $rank', 'score': 0.5},
        ],
        'fallback_hint': null,
      });
      expect([for (final c in value.candidates) c.rank], [1, 2, 3]);
      expect(value.isEmpty, isFalse);
    });

    test('treats an empty list with a preset hint as no match', () {
      final value = UtteranceDto.suggestions({
        'trace_id': 'abc',
        'candidates': <Object>[],
        'fallback_hint': 'preset',
      });
      expect(value.isEmpty, isTrue);
    });
  });

  group(UtteranceRepositoryImpl, () {
    test('builds suggest requests from the transcript and last log', () async {
      await sequence.save('41');
      when(() => source.suggest(any())).thenAnswer(
        (_) async => const Success(_suggestions),
      );
      await repository().suggest(_transcription);
      final body =
          verify(() => source.suggest(captureAny())).captured.single
              as Map<String, Object?>;
      expect(body['patient_prefix'], '물 좀 주세요');
      expect(body['final_transcript'], '물 좀 주세요');
      expect(body['source'], 'voice');
      expect(body['trace_id'], 't1');
      expect(body['previous_log_id'], 41);
      expect(body['client_ts'], startsWith('2026-10-31T23:05:00'));
      expect(body['client_ts'], matches(RegExp(r'[+-]\d\d:\d\d$')));
    });

    test(
      'logs a selection and keeps its log id for the next request',
      () async {
        repository().logSelected(
          transcription: _transcription,
          suggestions: _suggestions,
          candidate: _suggestions.candidates.first,
          latency: const Duration(milliseconds: 1500),
        );
        await pumpEventQueue();
        final body = sent.single;
        expect(body['action'], 'selected');
        expect(body['trace_id'], 's1');
        expect(body['selected_phrase'], '물 주세요');
        expect(body['selected_rank'], 1);
        expect(body['latency_ms'], 1500);
        expect(body['source'], 'voice');
        expect(body['candidates_shown'], [
          {
            'rank': 1,
            'text': '물 주세요',
            'score': 0.9,
            'reason_label': 'patient_frequency',
            'source': 'patient_log',
          },
          {
            'rank': 2,
            'text': '미지근한 물 주세요',
            'score': 0.7,
            'reason_label': null,
            'source': UtteranceRepositoryImpl.fallbackCandidateSource,
          },
        ]);
        expect(sequence.lastLogId, '77');
      },
    );

    test('logs a rejection without a selected phrase', () async {
      repository().logRejected(
        transcription: _transcription,
        suggestions: _suggestions,
        latency: Duration.zero,
      );
      await pumpEventQueue();
      final body = sent.single;
      expect(body['action'], 'rejected');
      expect(body['reject_reason'], 'not_this_phrase');
      expect(body['selected_phrase'], isNull);
      expect(body['selected_rank'], isNull);
      expect(sequence.lastLogId, isNull);
    });

    test('returns the sentence to speak from a bypass', () async {
      when(() => source.bypass(any())).thenAnswer(
        (_) async => const Success((logId: '9', finalText: '물 좀 주세요')),
      );
      final result = await repository().bypass(
        _transcription,
        latency: const Duration(milliseconds: 300),
      );
      expect(result, isA<Success<String>>());
      expect(sequence.lastLogId, '9');
    });
  });

  group(SelectionLogQueue, () {
    test('keeps logs after a network failure and sends them later', () async {
      var online = false;
      final queue = SelectionLogQueue(
        prefs: prefs,
        sequence: sequence,
        send: (body) async {
          if (!online) return const FailureResult(NetworkFailure());
          sent.add(body);
          return const Success('5');
        },
      );
      await queue.enqueue({'action': 'selected', 'n': 1});
      await queue.enqueue({'action': 'rejected', 'n': 2});
      expect(queue.pending, hasLength(2));
      online = true;
      await queue.flush();
      expect([for (final body in sent) body['n']], [1, 2]);
      expect(queue.pending, isEmpty);
      expect(sequence.lastLogId, '5');
    });

    test('drops payloads the server refuses as invalid', () async {
      final queue = SelectionLogQueue(
        prefs: prefs,
        sequence: sequence,
        send: (_) async =>
            const FailureResult(ValidationFailure(fieldErrors: {})),
      );
      await queue.enqueue({'action': 'selected'});
      expect(queue.pending, isEmpty);
    });

    test('caps the backlog at the most recent entries', () async {
      final queue = SelectionLogQueue(
        prefs: prefs,
        sequence: sequence,
        send: (_) async => const FailureResult(NetworkFailure()),
      );
      for (var i = 0; i < SelectionLogQueue.maxItems + 5; i++) {
        await queue.enqueue({'n': i});
      }
      expect(queue.pending, hasLength(SelectionLogQueue.maxItems));
      expect(queue.pending.first['n'], 5);
    });
  });
}
