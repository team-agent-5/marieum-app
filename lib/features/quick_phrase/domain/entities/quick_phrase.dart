import 'package:equatable/equatable.dart';

enum QuickPhraseIcon {
  water,
  toilet,
  yes,
  no,
  thanks,
  sorry,
  pain,
  temperature,
  help,
  call,
  text,
}

class QuickPhrase extends Equatable {
  const QuickPhrase({
    required this.id,
    required this.text,
    required this.icon,
    this.presetIndex,
  });

  final String id;
  final String text;
  final QuickPhraseIcon icon;

  /// Server catalog position (1~10) for default phrases; null when user-added.
  final int? presetIndex;

  @override
  List<Object?> get props => [id, text, icon, presetIndex];
}

abstract final class QuickPhraseRules {
  static const maxLength = 20;
  static const minCount = 3;
  static const maxCount = 20;
}

const defaultQuickPhrases = <QuickPhrase>[
  QuickPhrase(
    id: 'preset-1',
    text: '물 주세요',
    icon: QuickPhraseIcon.water,
    presetIndex: 1,
  ),
  QuickPhrase(
    id: 'preset-2',
    text: '화장실 가고 싶어요',
    icon: QuickPhraseIcon.toilet,
    presetIndex: 2,
  ),
  QuickPhrase(
    id: 'preset-3',
    text: '네',
    icon: QuickPhraseIcon.yes,
    presetIndex: 3,
  ),
  QuickPhrase(
    id: 'preset-4',
    text: '아니요',
    icon: QuickPhraseIcon.no,
    presetIndex: 4,
  ),
  QuickPhrase(
    id: 'preset-5',
    text: '고마워요',
    icon: QuickPhraseIcon.thanks,
    presetIndex: 5,
  ),
  QuickPhrase(
    id: 'preset-6',
    text: '미안해요',
    icon: QuickPhraseIcon.sorry,
    presetIndex: 6,
  ),
  QuickPhrase(
    id: 'preset-7',
    text: '아파요',
    icon: QuickPhraseIcon.pain,
    presetIndex: 7,
  ),
  QuickPhrase(
    id: 'preset-8',
    text: '춥거나 더워요',
    icon: QuickPhraseIcon.temperature,
    presetIndex: 8,
  ),
  QuickPhrase(
    id: 'preset-9',
    text: '도와주세요',
    icon: QuickPhraseIcon.help,
    presetIndex: 9,
  ),
  QuickPhrase(
    id: 'preset-10',
    text: '불러주세요',
    icon: QuickPhraseIcon.call,
    presetIndex: 10,
  ),
];
