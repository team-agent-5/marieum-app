import 'dart:convert';

import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/quick_phrase.dart';

class QuickPhraseLocalStore {
  QuickPhraseLocalStore(this._prefs);
  final PrefsStore _prefs;

  List<QuickPhrase>? read() {
    final raw = _prefs.readString(PrefsKeys.quickPhrases);
    if (raw == null) return null;
    try {
      final items = (jsonDecode(raw) as List<Object?>)
          .map((item) => _decode(item! as Map<String, Object?>))
          .toList(growable: false);
      return items.isEmpty ? null : items;
    } on Object {
      return null;
    }
  }

  Future<void> write(List<QuickPhrase> phrases) => _prefs.writeString(
    PrefsKeys.quickPhrases,
    jsonEncode([for (final phrase in phrases) _encode(phrase)]),
  );

  static Map<String, Object?> _encode(QuickPhrase phrase) => {
    'id': phrase.id,
    'text': phrase.text,
    'icon': phrase.icon.name,
    'preset_index': phrase.presetIndex,
  };

  static QuickPhrase _decode(Map<String, Object?> json) => QuickPhrase(
    id: json['id']! as String,
    text: json['text']! as String,
    icon:
        QuickPhraseIcon.values.asNameMap()[json['icon']] ??
        QuickPhraseIcon.text,
    presetIndex: json['preset_index'] as int?,
  );
}
