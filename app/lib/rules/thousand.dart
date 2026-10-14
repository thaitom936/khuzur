import 'card.dart';
import 'rules.dart' show TrickCard;

int thousandPoints(int card) =>
    const {9: 0, 10: 10, 11: 2, 12: 3, 13: 4, 14: 11}[rankOf(card)]!;
int thousandStrength(int card) =>
    const {9: 0, 11: 1, 12: 2, 13: 3, 10: 4, 14: 5}[rankOf(card)]!;
int thousandMarriagePoints(int suit) => const [60, 80, 100, 40][suit];
List<int> thousandMarriages(List<int> hand) => [
  for (var s = 0; s < 4; s++)
    if (hand.contains(s * 16 + 12) && hand.contains(s * 16 + 13)) s,
];
int thousandBidCap(List<int> hand) =>
    120 +
    thousandMarriages(
      hand,
    ).fold(0, (total, s) => total + thousandMarriagePoints(s));
List<int> thousandLegalCards(List<int> hand, List<TrickCard> trick, int trump) {
  if (trick.isEmpty) return [...hand];
  final lead = suitOf(trick.first.card);
  final same = hand.where((c) => suitOf(c) == lead).toList();
  if (same.isNotEmpty) return same;
  final trumps = hand.where((c) => suitOf(c) == trump).toList();
  return trumps.isNotEmpty ? trumps : [...hand];
}

bool thousandCanAnnounce(
  List<int> hand,
  List<TrickCard> trick,
  int tricksWon,
  int card,
) =>
    trick.isEmpty &&
    tricksWon > 0 &&
    (rankOf(card) == 12 || rankOf(card) == 13) &&
    thousandMarriages(hand).contains(suitOf(card));
