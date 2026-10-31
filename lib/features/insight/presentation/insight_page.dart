import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/feature_panel.dart';
import 'package:marieum_app/core/ui/key_text.dart';
import 'package:marieum_app/features/insight/domain/insight_summary.dart';
import 'package:marieum_app/features/insight/presentation/insight_cubit.dart';

class InsightPage extends StatelessWidget {
  const InsightPage({required this.createCubit, super.key});
  final InsightCubit Function() createCubit;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = createCubit();
      unawaited(cubit.load());
      return cubit;
    },
    child: const FeaturePage(title: '개인화 현황', child: InsightView()),
  );
}

class InsightView extends StatelessWidget {
  const InsightView({super.key});
  @override
  Widget build(BuildContext context) => BlocBuilder<InsightCubit, InsightState>(
    builder: (context, state) {
      final summary = state.summary;
      if (state.status == InsightStatus.failure) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(state.failure!.message),
              TextButton(
                onPressed: () => unawaited(context.read<InsightCubit>().load()),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        );
      }
      if (summary == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (summary.learning)
            _Learning(summary: summary)
          else ...[
            const Text('최근 7일 동안의 말하기를 정리했어요.', style: AppTokens.copy),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Stat(label: '이번 주 요청', value: '${summary.total}회'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(
                    label: '첫 후보 선택',
                    value: '${(summary.rankRatio(1) * 100).round()}%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text('추천 후보 선택 순위', style: AppTokens.copy),
            const SizedBox(height: 7),
            _Ranks(summary: summary),
            const SizedBox(height: 18),
            const Text('자주 쓴 말', style: AppTokens.copy),
            const SizedBox(height: 7),
            FeaturePanel(
              child: Column(
                children: [
                  for (final item in summary.frequent)
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: KeyText(
                                  item.text,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text('${item.count}회'),
                            ],
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: item.count / summary.frequent.first.count,
                            minHeight: 5,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          const FeaturePanel(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, color: AppTokens.primaryStrong),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '내 데이터로만 배워요',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '음성 원본은 저장하지 않고, 선택한 문장 기록만 추천에 써요.',
                          style: AppTokens.copy,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _Learning extends StatelessWidget {
  const _Learning({required this.summary});
  final InsightSummary summary;
  @override
  Widget build(BuildContext context) => FeaturePanel(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(
            Icons.speed_rounded,
            size: 60,
            color: AppTokens.primaryStrong,
          ),
          const SizedBox(height: 20),
          const Text(
            '내 말을 배우는 중이에요',
            textAlign: TextAlign.center,
            style: AppTokens.title,
          ),
          const SizedBox(height: 10),
          const Text(
            '후보를 선택한 기록이 10번 쌓이면 추천이 얼마나 잘 맞는지 보여드려요.',
            textAlign: TextAlign.center,
            style: AppTokens.copy,
          ),
          const SizedBox(height: 20),
          LinearProgressIndicator(
            value: summary.voiceCount / 10,
            minHeight: 8,
            semanticsLabel: '학습 진행',
            semanticsValue: '${summary.voiceCount} / 10번',
          ),
          const SizedBox(height: 10),
          Text('${summary.voiceCount} / 10번'),
        ],
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => FeaturePanel(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTokens.copy),
          const SizedBox(height: 8),
          Text(value, style: AppTokens.title),
        ],
      ),
    ),
  );
}

class _Ranks extends StatelessWidget {
  const _Ranks({required this.summary});
  final InsightSummary summary;
  static const List<Color> colors = [
    AppTokens.primaryStrong,
    AppTokens.primary,
    AppTokens.lineStrong,
  ];
  @override
  Widget build(BuildContext context) => FeaturePanel(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 14,
                child: Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      if (summary.rankCounts[i] > 0)
                        Expanded(
                          flex: summary.rankCounts[i],
                          child: ColoredBox(
                            color: colors[i],
                            child: const SizedBox.expand(),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (var rank = 1; rank <= 3; rank++)
                Text('$rank번째 ${(summary.rankRatio(rank) * 100).round()}%'),
            ],
          ),
        ],
      ),
    ),
  );
}
