import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/speak/data/dto/utterance_dto.dart';
import 'package:marieum_app/features/speak/domain/entities/utterance.dart';

void main() {
  group('Suggestion mode decoding', () {
    const common = <String, Object?>{
      'trace_id': 'trace',
      'generated_at': '2026-11-01T00:00:00Z',
      'generation_latency_ms': 0,
      'asr_confidence': 0.99,
      'cold_start': false,
    };
    const verbatim = {'text': '물 주세요', 'source': 'asr_verbatim'};
    const suggestion = {
      'phrase': '미지근한 물 주세요',
      'reason_display': '저녁에 자주 요청하신 음료',
      'modal_text': '미지근한 물 주세요라고 말할까요?',
      'confidence': 0.86,
    };
    test(
      'decodes proactive text, modal wording and reason '
      'without candidate scores',
      () {
        final value = UtteranceDto.suggestions({
          ...common,
          'mode': 'proactive',
          'branch': 'high',
          'verbatim': verbatim,
          'suggestion': suggestion,
        });
        expect(value.mode, SuggestionMode.proactive);
        expect(value.verbatim?.text, '물 주세요');
        expect(value.verbatim?.source, CandidateSource.asrVerbatim);
        expect(value.proactiveSuggestion?.candidate.text, suggestion['phrase']);
        expect(
          value.proactiveSuggestion?.candidate.reasonDisplay,
          suggestion['reason_display'],
        );
        expect(value.proactiveSuggestion?.modalText, suggestion['modal_text']);
        expect(value.candidates, hasLength(2));
        expect(value.generatedAt, DateTime.utc(2026, 11));
        expect(value.asrConfidence, 0.99);
        expect(value.branch, 'high');
      },
    );
    test('accepts proactive without an optional suggestion', () {
      final value = UtteranceDto.suggestions({
        ...common,
        'mode': 'proactive',
        'verbatim': verbatim,
        'suggestion': null,
      });
      expect(value.proactiveSuggestion, isNull);
      expect(value.verbatim?.text, '물 주세요');
    });
    test('decodes three choices and preserves sources and Korean reasons', () {
      final value = UtteranceDto.suggestions({
        ...common,
        'mode': 'candidates',
        'candidates': [
          {
            'rank': 1,
            'text': '물',
            'source': 'asr_verbatim',
            'reason_display': '방금 들린 그대로',
            'score': null,
          },
          {
            'rank': 2,
            'text': '미지근한 물 주세요',
            'source': 'llm_inference',
            'reason_display': '자주 선택하신 말',
          },
          {'rank': 3, 'text': '따뜻한 물 주세요', 'source': 'llm_inference'},
        ],
      });
      expect(value.mode, SuggestionMode.candidates);
      expect(value.candidates.map((c) => c.source), [
        CandidateSource.asrVerbatim,
        CandidateSource.llmInference,
        CandidateSource.llmInference,
      ]);
      expect(value.candidates.first.reasonDisplay, '방금 들린 그대로');
      expect(value.candidates.first.score, 0);
    });
    test(
      'decodes the single object rather than expecting a candidates list',
      () {
        final value = UtteranceDto.suggestions({
          ...common,
          'mode': 'single',
          'candidate': {
            'rank': 1,
            'text': '물 주세요',
            'reason_display': '이 시간대에 자주 요청하신 문장',
            'source': 'llm_reconstruction',
          },
        });
        expect(value.mode, SuggestionMode.single);
        expect(
          value.candidates.single.source,
          CandidateSource.llmReconstruction,
        );
        expect(value.candidates.single.reasonDisplay, '이 시간대에 자주 요청하신 문장');
      },
    );
    test(
      'keeps retry as a successful mode and preserves its message verbatim',
      () {
        final value = UtteranceDto.suggestions({
          ...common,
          'mode': 'retry',
          'message': '잘 못 들었어요. 다시 말씀해 주세요.',
        });
        expect(value.mode, SuggestionMode.retry);
        expect(value.retryMessage, '잘 못 들었어요. 다시 말씀해 주세요.');
        expect(value.candidates, isEmpty);
      },
    );
    test('keeps the original generation source names in selection logs', () {
      for (final entry in {
        CandidateSource.asrVerbatim: 'asr_verbatim',
        CandidateSource.llmInference: 'llm_inference',
        CandidateSource.llmReconstruction: 'llm_reconstruction',
      }.entries) {
        final snapshot = UtteranceDto.candidateSnapshot(
          Candidate(rank: 1, text: '문장', score: 0, source: entry.key),
          fallbackSource: 'catalog',
        );
        expect(snapshot['source'], entry.value);
      }
    });

    test('rejects an unknown mode or missing required mode payload', () {
      for (final body in [
        {'mode': 'other'},
        {'mode': 'proactive', 'verbatim': <String, Object?>{}},
        {
          'mode': 'single',
          'candidate': {'rank': 1},
        },
        {'mode': 'candidates'},
        {'mode': 'retry'},
      ]) {
        expect(
          () => UtteranceDto.suggestions({...common, ...body}),
          throwsA(anyOf(isA<FormatException>(), isA<TypeError>())),
        );
      }
    });
  });
}
