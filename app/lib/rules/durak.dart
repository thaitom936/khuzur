import 'card.dart';

bool durakBeats(int attack, int cover, int trump) =>
    (suitOf(attack) == suitOf(cover) && rankOf(cover) > rankOf(attack)) ||
    (suitOf(cover) == trump && suitOf(attack) != trump);

class DurakPair {
  final int attack;
  final int attacker;
  final int? cover;
  final int? defender;
  const DurakPair(this.attack, this.attacker, [this.cover, this.defender]);
}

class DurakHint {
  final String action;
  final List<int> cards;
  final int? target;
  const DurakHint(this.action, [this.cards = const [], this.target]);
}

DurakHint durakHint(
  List<int> hand,
  List<DurakPair> pairs,
  String stage,
  int trump,
  int limit,
  bool transfer,
  int nextHandCount, [
  int maxAttacks = 6,
]) {
  final sorted = [...hand]
    ..sort((a, b) {
      final va = rankOf(a) + (suitOf(a) == trump ? 100 : 0);
      final vb = rankOf(b) + (suitOf(b) == trump ? 100 : 0);
      return va == vb ? a.compareTo(b) : va.compareTo(vb);
    });
  if (stage == 'attack') {
    return sorted.isEmpty
        ? const DurakHint('finish')
        : DurakHint('attack', [sorted.first]);
  }
  if (stage == 'add') {
    final ranks = {
      for (final p in pairs) rankOf(p.attack),
      for (final p in pairs)
        if (p.cover != null) rankOf(p.cover!),
    };
    if (pairs.length < limit) {
      for (final c in sorted) {
        if (ranks.contains(rankOf(c))) return DurakHint('attack', [c]);
      }
    }
    return const DurakHint('finish');
  }
  final target = pairs.indexWhere((p) => p.cover == null);
  if (target >= 0) {
    for (final c in sorted) {
      if (durakBeats(pairs[target].attack, c, trump)) {
        return DurakHint('defend', [c], target);
      }
    }
    if (transfer &&
        pairs.length < nextHandCount &&
        pairs.length < maxAttacks &&
        pairs.every(
          (p) =>
              p.cover == null && rankOf(p.attack) == rankOf(pairs.first.attack),
        )) {
      for (final c in sorted) {
        if (rankOf(c) == rankOf(pairs.first.attack)) {
          return DurakHint('transfer', [c]);
        }
      }
    }
  }
  return const DurakHint('take');
}
