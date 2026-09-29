/// Card encoding shared with the Lua engine and the wire protocol.
///
/// A card is an integer: `suit * 16 + rank`, where
/// suit: 0=clubs(C) 1=diamonds(D) 2=hearts(H) 3=spades(S),
/// rank: 7..14 (11=J 12=Q 13=K 14=A).
/// The string form is `<rank><suit>`, e.g. "7C", "TD", "AH".
library;

const rankChars = {7: '7', 8: '8', 9: '9', 10: 'T', 11: 'J', 12: 'Q', 13: 'K', 14: 'A'};
const suitChars = {0: 'C', 1: 'D', 2: 'H', 3: 'S'};

final _charRanks = {for (final e in rankChars.entries) e.value: e.key};
final _charSuits = {for (final e in suitChars.entries) e.value: e.key};

int parseCard(String s) {
  final rank = _charRanks[s[0]];
  final suit = _charSuits[s[1]];
  if (rank == null || suit == null) {
    throw ArgumentError('bad card string: $s');
  }
  return suit * 16 + rank;
}

String cardString(int c) => '${rankChars[c % 16]}${suitChars[c ~/ 16]}';

int suitOf(int c) => c ~/ 16;

int rankOf(int c) => c % 16;

/// All 32 cards of the Muushig deck.
List<int> fullDeck() => [
  for (var suit = 0; suit < 4; suit++)
    for (var rank = 7; rank <= 14; rank++) suit * 16 + rank,
];
