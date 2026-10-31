abstract final class LivePhrasePolicy {
  static String displayText(String text) =>
      text.replaceAll('\uFFFD', '').trim();

  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');

  /// Longer than a patient says in one breath.
  static const maxLength = 60;

  /// A recognizer stuck in a loop: the same words over and over, or far
  /// more text than one sentence. These came back with high confidence and
  /// were read aloud for a quarter of a minute.
  static bool isRunaway(String text) {
    final compact = _normalize(text);
    if (compact.runes.length > maxLength) return true;
    final words = text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    // The same piece over and over with no spaces between, as in
    // "자동차를타고자동차를타고자동차를타고".
    if (RegExp(r'(.{2,8})\1\1').hasMatch(compact)) return true;
    // A long phrase said twice, as when the loop repeats a whole clause.
    if (RegExp(r'(.{8,}).*\1').hasMatch(compact)) return true;
    for (var n = 1; n <= 4; n++) {
      final counts = <String, int>{};
      for (var i = 0; i + n <= words.length; i++) {
        final gram = words.sublist(i, i + n).join(' ');
        final count = counts[gram] = (counts[gram] ?? 0) + 1;
        if (count >= (n == 1 ? 4 : 3)) return true;
      }
    }
    return false;
  }

  /// Syllables per second of voice above which text is taken as made up.
  /// Voice counts only the louder parts of speech, so this is generous.
  static const maxRate = 10;

  /// More text than the voice heard could hold: the recognizer added words
  /// of its own, as in a sentence from its training or a long tail.
  static bool isOverlong(String text, Duration voice) =>
      _normalize(text).runes.length >
      voice.inMilliseconds * maxRate ~/ 1000 + 4;

  /// Word endings that leave a Korean sentence open: particles and
  /// connective endings after which more is expected.
  static const _openEndings = [
    '는데',
    '은데',
    '인데',
    '지만',
    '면서',
    '다가',
    '려고',
    '어서',
    '아서',
    '해서',
    '니까',
    '에서',
    '에게',
    '한테',
    '부터',
    '까지',
    '이랑',
    '으로',
    '고',
    '서',
    '면',
    '며',
    '는',
    '은',
    '을',
    '를',
    '에',
    '의',
    '와',
    '과',
    '로',
    '랑',
    '게',
    '데',
  ];

  /// Whether [text] stops where a sentence cannot end, as when a patient
  /// who speaks slowly pauses midway and the recognizer closes it there.
  static bool isUnfinished(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || RegExp(r'[.?!]$').hasMatch(trimmed)) return false;
    final last = trimmed.split(RegExp(r'\s+')).last;
    if (last.runes.length < 2) return false;
    return _openEndings.any(last.endsWith);
  }

  /// Too short to be worth a line of its own, like a single syllable left
  /// over from the app's own voice.
  static bool isFragment(String text) => _normalize(text).runes.length <= 2;

  /// Length of the leading words [previous] and [current] agree on, the
  /// part of a changing reading that is likely to stay.
  static int stablePrefix(String previous, String current) {
    final a = previous.split(' ');
    final b = current.split(' ');
    var length = 0;
    for (var i = 0; i < a.length && i < b.length && a[i] == b[i]; i++) {
      length += b[i].length + (i == 0 ? 0 : 1);
    }
    return length;
  }

  static bool isEcho(String spoken, String heard) {
    final a = _normalize(spoken).runes.toList();
    final b = _normalize(heard).runes.toList();
    if (a.length < 3 || b.length < 3) return false;
    var row = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final next = <int>[i + 1];
      for (var j = 0; j < b.length; j++) {
        final substitution = row[j] + (a[i] == b[j] ? 0 : 1);
        final deletion = row[j + 1] + 1;
        final insertion = next[j] + 1;
        next.add(
          [substitution, deletion, insertion].reduce((x, y) => x < y ? x : y),
        );
      }
      row = next;
    }
    final longest = a.length > b.length ? a.length : b.length;
    return 1 - row.last / longest >= 0.7;
  }
}
