abstract final class LivePhrasePolicy {
  static String displayText(String text) =>
      text.replaceAll('\uFFFD', '').trim();

  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');

  /// A phrase of four or more letters said again right after itself, as
  /// in "나연이는 사다릅니다 나연이는 사다릅니다".
  static bool repeats(String text) =>
      RegExp(r'(.{4,})\1').hasMatch(_normalize(text));

  /// The recognizer sometimes starts the next sentence on the end of the
  /// last one, as in "가방이" after "책상이 가방이 있습니다"; such a piece
  /// was already said.
  static bool isLeftover(String heard, String previous) {
    final piece = _normalize(heard);
    final whole = _normalize(previous);
    return piece.isNotEmpty &&
        piece.length < whole.length &&
        whole.contains(piece);
  }

  /// Too short to stand for a sentence.
  static bool isFragment(String text) => _normalize(text).runes.length <= 2;

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
