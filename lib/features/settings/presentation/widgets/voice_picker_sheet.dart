import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/settings/presentation/cubit/settings_cubit.dart';

class VoiceChoice {
  const VoiceChoice(this.id, {this.preview = false});
  final String? id;
  final bool preview;
}

class VoicePickerSheet extends StatelessWidget {
  const VoicePickerSheet({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final voices = state.voices;
        final selectedId =
            voices?.any((v) => v.id == state.settings.voiceId) ?? false
            ? state.settings.voiceId
            : null;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '목소리',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            _VoiceOption(name: '자동(추천)', selected: selectedId == null),
            if (voices == null)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              for (final voice in voices)
                _VoiceOption(
                  id: voice.id,
                  name: voice.name,
                  description: [
                    if (voice.isHighQuality) '고품질' else '기본',
                    if (voice.requiresNetwork) '인터넷 필요',
                  ].join(' · '),
                  selected: selectedId == voice.id,
                ),
              if (!voices.any((v) => v.isHighQuality))
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Text(
                    Theme.of(context).platform == TargetPlatform.iOS
                        ? '설정 > 손쉬운 사용 > 읽기 및 말하기 > 음성 > 한국어에서 '
                              '고품질 음성을 내려받으면 더 자연스러워요'
                        : 'Google 음성 서비스를 설치하거나 업데이트하면 더 자연스러운 목소리를 쓸 수 있어요',
                    style: AppTokens.copy,
                  ),
                ),
            ],
          ],
        );
      },
    ),
  );
}

class _VoiceOption extends StatelessWidget {
  const _VoiceOption({
    required this.name,
    required this.selected,
    this.id,
    this.description,
  });

  final String? id;
  final String name;
  final String? description;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Material(
      color: selected ? AppTokens.surfaceBlue : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTokens.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              selected: selected,
              button: true,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(VoiceChoice(id)),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: AppTokens.primaryStrong,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name),
                              if (description != null)
                                Text(description!, style: AppTokens.copy),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(76, 48)),
            onPressed: () =>
                Navigator.of(context).pop(VoiceChoice(id, preview: true)),
            child: Semantics(
              label: '$name 미리듣기',
              excludeSemantics: true,
              child: const Text('미리듣기'),
            ),
          ),
        ],
      ),
    ),
  );
}
