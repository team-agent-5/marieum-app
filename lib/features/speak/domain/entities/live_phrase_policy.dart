abstract final class LivePhrasePolicy {
  static String displayText(String text) =>
      text.replaceAll('\uFFFD', '').trim();

  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');

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
