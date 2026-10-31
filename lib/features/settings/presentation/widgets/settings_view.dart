import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/tts/tts_port.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_segmented_control.dart';
import 'package:marieum_app/core/ui/feature_panel.dart';
import 'package:marieum_app/core/ui/key_text.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';
import 'package:marieum_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:marieum_app/features/settings/presentation/widgets/voice_picker_sheet.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({required this.settings, super.key});
  final AppSettings settings;

  Future<void> _chooseVoice(BuildContext context) async {
    final cubit = context.read<SettingsCubit>();
    unawaited(cubit.loadVoices());
    final choice = await showModalBottomSheet<VoiceChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: const VoicePickerSheet(),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice.preview) {
      await cubit.previewVoice(choice.id, () async {
        if (!context.mounted) return;
        await context.push<void>(
          '/speak/playback',
          extra: const PlaybackRequest(
            text: '미지근한 물 주세요',
            origin: PlaybackOrigin.preview,
          ),
        );
      });
    } else {
      await cubit.setVoice(choice.id);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const Text('내가 듣고 보기 편한 방식으로 조정해요.', style: AppTokens.copy),
      const SizedBox(height: 18),
      const Text('음성', style: AppTokens.copy),
      const SizedBox(height: 7),
      FeaturePanel(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.record_voice_over_outlined,
                    color: AppTokens.primaryStrong,
                  ),
                  title: const Text('목소리'),
                  subtitle: Text(
                    settings.voiceId == null ? '자동(추천)' : '선택한 목소리',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => unawaited(_chooseVoice(context)),
                ),
              ),
              const Divider(height: 28),
              const _SettingLabel(
                icon: Icons.speed_rounded,
                text: '말하는 속도',
              ),
              AdaptiveSegmentedControl<TtsRate>(
                value: settings.rate,
                children: const {
                  TtsRate.slow: Text('느림'),
                  TtsRate.normal: Text('보통'),
                  TtsRate.fast: Text('빠름'),
                },
                onChanged: (value) =>
                    unawaited(context.read<SettingsCubit>().setRate(value)),
              ),
              const Divider(height: 28),
              const _SettingLabel(
                icon: Icons.volume_up_outlined,
                text: '목소리 크기',
              ),
              AdaptiveSegmentedControl<TtsVolume>(
                value: settings.volume,
                children: const {
                  TtsVolume.soft: Text('작게'),
                  TtsVolume.normal: Text('보통'),
                  TtsVolume.loud: Text('크게'),
                },
                onChanged: (value) => unawaited(
                  context.read<SettingsCubit>().setVolume(value),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: () => unawaited(
                  context.push<void>(
                    '/speak/playback',
                    extra: const PlaybackRequest(
                      text: '미지근한 물 주세요',
                      origin: PlaybackOrigin.preview,
                    ),
                  ),
                ),
                child: const KeyText('설정한 목소리 미리듣기'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      const Text('화면', style: AppTokens.copy),
      const SizedBox(height: 7),
      FeaturePanel(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SettingLabel(
                icon: Icons.text_fields_rounded,
                text: '글자 크기',
              ),
              const Text('핵심 문장을 더 크게', style: AppTokens.copy),
              AdaptiveSegmentedControl<bool>(
                value: settings.largeText,
                children: const {false: Text('보통'), true: Text('크게')},
                onChanged: (value) => unawaited(
                  context.read<SettingsCubit>().setLargeText(value: value),
                ),
              ),
            ],
          ),
        ),
      ),
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
                      '개인정보 보호',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '음성 원본은 저장하지 않고 분석이 끝나면 바로 폐기해요.',
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
}

class _SettingLabel extends StatelessWidget {
  const _SettingLabel({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, color: AppTokens.primaryStrong),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
