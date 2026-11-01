import 'dart:async';

import 'package:marieum_app/core/storage/prefs_store.dart';

/// How fast the patient speaks. Slow speakers pause inside a sentence, so
/// the app waits longer before taking a pause as the end of it.
enum SpeechPace {
  auto('자동'),
  slow('천천히'),
  normal('보통'),
  fast('빠르게');

  const SpeechPace(this.label);
  final String label;
}

/// Resolves the pace in use: the patient's choice, or with [SpeechPace.auto]
/// the pace measured from what they said.
class SpeechPaceTracker {
  SpeechPaceTracker(this._prefs);

  final PrefsStore _prefs;

  /// Syllables per second below or above which speech counts as slow or
  /// fast, pauses included.
  static const slowRate = 2.5;
  static const fastRate = 4.5;

  /// Weight of the newest measurement in the running average.
  static const _weight = 0.3;

  SpeechPace get setting {
    final stored = _read(() => _prefs.readString(PrefsKeys.speechPace));
    return SpeechPace.values.where((p) => p.name == stored).firstOrNull ??
        SpeechPace.auto;
  }

  /// Running average of measured syllables per second, if any.
  double? get measuredRate => double.tryParse(
    _read(() => _prefs.readString(PrefsKeys.speechRate)) ?? '',
  );

  SpeechPace get effective {
    final chosen = setting;
    if (chosen != SpeechPace.auto) return chosen;
    final rate = measuredRate;
    if (rate == null) return SpeechPace.normal;
    if (rate < slowRate) return SpeechPace.slow;
    if (rate > fastRate) return SpeechPace.fast;
    return SpeechPace.normal;
  }

  /// How long a sentence left unfinished waits for the rest of it.
  Duration get continuationWait => switch (effective) {
    SpeechPace.slow => const Duration(milliseconds: 2000),
    SpeechPace.fast => const Duration(milliseconds: 700),
    SpeechPace.normal || SpeechPace.auto => const Duration(milliseconds: 1200),
  };

  /// Records how fast [text] was said over [spoken]. Very short sayings
  /// tell too little and are skipped.
  void observe(String text, Duration spoken) {
    final syllables = syllableCount(text);
    if (syllables < 3 || spoken < const Duration(milliseconds: 600)) return;
    final rate = (syllables * 1000 / spoken.inMilliseconds).clamp(0.5, 10.0);
    final previous = measuredRate;
    final average = previous == null
        ? rate
        : previous * (1 - _weight) + rate * _weight;
    unawaited(
      _prefs
          .writeString(PrefsKeys.speechRate, average.toStringAsFixed(2))
          .catchError((Object _) {}),
    );
  }

  /// Hangul syllables, counted with any other letters and digits.
  static int syllableCount(String text) =>
      RegExp(r'[\p{L}\p{N}]', unicode: true).allMatches(text).length;

  static T? _read<T>(T? Function() read) {
    try {
      return read();
    } on Object {
      return null;
    }
  }
}
