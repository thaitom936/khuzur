import 'card.dart';

/// Mongol 13 friend-room combinations; separate from Muushig trump rules.
int m13Rank(int c) => rankOf(c) == 2 ? 15 : rankOf(c);
int m13Suit(int c) => const [1, 0, 2, 3][suitOf(c)];
int m13Value(int c) => m13Rank(c) * 4 + m13Suit(c);

class M13Combo {
  final String kind;
  final int count;
  final List<int> strength;
  const M13Combo(this.kind, this.count, this.strength);
  bool beats(M13Combo other) {
    if (count != other.count) return false;
    for (var i = 0; i < strength.length; i++) {
      if (strength[i] != other.strength[i]) {
        return strength[i] > other.strength[i];
      }
    }
    return false;
  }
}

M13Combo? m13Combo(List<int> cards) {
  if (cards.isEmpty ||
      cards.length > 5 ||
      cards.toSet().length != cards.length) {
    return null;
  }
  final groups = <int, int>{};
  for (final c in cards) {
    if (rankOf(c) < 2 || rankOf(c) > 14 || suitOf(c) < 0 || suitOf(c) > 3) {
      return null;
    }
    groups.update(m13Rank(c), (v) => v + 1, ifAbsent: () => 1);
  }
  final sorted = [...cards]..sort((a, b) => m13Value(b).compareTo(m13Value(a)));
  if (cards.length <= 4) {
    if (groups.length != 1) return null;
    return M13Combo(
      const ['', 'single', 'pair', 'triple', 'four'][cards.length],
      cards.length,
      [m13Value(sorted.first)],
    );
  }
  final ranks = groups.keys.toList()..sort();
  var straight = 0;
  if (ranks.length == 5) {
    final natural = cards.map(rankOf).toList()..sort();
    if (natural.join(',') == '2,3,4,5,14') {
      straight = 5;
    } else if (natural.last - natural.first == 4 && natural.last <= 14) {
      straight = natural.last;
    }
  }
  final flush = cards.every((c) => suitOf(c) == suitOf(cards.first));
  if (straight > 0 && flush) {
    return M13Combo('straightFlush', 5, [
      4,
      straight,
      m13Suit(cards.first),
      0,
      0,
      0,
      0,
    ]);
  }
  final four = groups.entries.where((e) => e.value == 4).firstOrNull;
  if (four != null) return M13Combo('fourOne', 5, [3, four.key, 0, 0, 0, 0, 0]);
  final three = groups.entries.where((e) => e.value == 3).firstOrNull;
  if (three != null && groups.length == 2) {
    return M13Combo('fullHouse', 5, [2, three.key, 0, 0, 0, 0, 0]);
  }
  if (flush) {
    return M13Combo('flush', 5, [
      1,
      ...sorted.map(m13Rank),
      m13Suit(sorted.first),
    ]);
  }
  if (straight > 0) {
    final high = cards.firstWhere((c) => rankOf(c) == straight);
    return M13Combo('straight', 5, [0, straight, m13Suit(high), 0, 0, 0, 0]);
  }
  return null;
}

bool m13CanPlay(List<int> hand, List<int> cards, List<int> last, int? opening) {
  if (!cards.every(hand.contains) ||
      (opening != null && !cards.contains(opening))) {
    return false;
  }
  final combo = m13Combo(cards);
  if (combo == null) return false;
  return last.isEmpty || combo.beats(m13Combo(last)!);
}

/// Up to C(13,5) combinations: deterministic legal hint, also used by tests.
List<int> m13Hint(List<int> hand, List<int> last, int? opening) {
  final sorted = [...hand]..sort((a, b) => m13Value(a).compareTo(m13Value(b)));
  for (final n in last.isEmpty ? [5, 4, 3, 2, 1] : [last.length]) {
    List<int>? found;
    void visit(int start, List<int> picked) {
      if (found != null) return;
      if (picked.length == n) {
        if (m13CanPlay(hand, picked, last, opening)) found = [...picked];
        return;
      }
      for (var i = start; i <= sorted.length - (n - picked.length); i++) {
        visit(i + 1, [...picked, sorted[i]]);
        if (found != null) return;
      }
    }

    visit(0, []);
    if (found != null) return found!;
  }
  return [];
}
