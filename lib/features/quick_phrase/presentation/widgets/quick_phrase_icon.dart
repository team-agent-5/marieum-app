import 'package:flutter/material.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/quick_phrase.dart';

IconData quickPhraseIconData(QuickPhraseIcon icon) => switch (icon) {
  QuickPhraseIcon.water => Icons.water_drop_outlined,
  QuickPhraseIcon.toilet => Icons.wc_rounded,
  QuickPhraseIcon.yes => Icons.thumb_up_outlined,
  QuickPhraseIcon.no => Icons.thumb_down_outlined,
  QuickPhraseIcon.thanks => Icons.favorite_border_rounded,
  QuickPhraseIcon.sorry => Icons.favorite_border_rounded,
  QuickPhraseIcon.pain => Icons.healing_outlined,
  QuickPhraseIcon.temperature => Icons.thermostat_rounded,
  QuickPhraseIcon.help => Icons.back_hand_outlined,
  QuickPhraseIcon.call => Icons.notifications_none_rounded,
  QuickPhraseIcon.text => Icons.short_text_rounded,
};
