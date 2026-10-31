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
