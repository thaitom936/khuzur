/// Dealing: shuffles the 32-card deck and creates a round.
library;

import 'dart:math';

import 'card.dart';
import 'rules.dart';

/// Deals a new round: 5 cards each, one face-up trump, the rest is stock.
GameState deal({
  required int numPlayers,
  required int dealer,
  required List<int> scores,
  RuleConfig config = const RuleConfig(),
  Random? random,
}) {
  final rng = random ?? Random.secure();
  final deck = fullDeck()..shuffle(rng);

  var i = 0;
  final hands = [
    for (var seat = 0; seat < numPlayers; seat++)
      [for (var k = 0; k < 5; k++) cardString(deck[i++])],
  ];
  final trump = cardString(deck[i++]);
  final stock = [for (; i < deck.length; i++) cardString(deck[i])];

  return GameState.newRound(
    hands: hands,
    trump: trump,
    stock: stock,
    dealer: dealer,
    config: config,
    scores: scores,
  );
}
