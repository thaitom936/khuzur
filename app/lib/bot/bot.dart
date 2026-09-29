/// AI players for the single-player mode.
///
/// Bots are stateless: every choice is a function of the current [GameState]
/// and the seat they play. The caller (the game controller) is responsible
/// for falling back to "play" when a bot wants to pass but passing is
/// illegal.
library;

import 'dart:math';

import '../rules/card.dart';
import '../rules/rules.dart';

abstract class Bot {
  /// Phase deciding: true to play, false to (try to) pass.
  bool decidePlay(GameState state, int seat);

  /// Phase exchanging: card strings to discard (already limited by the
  /// stock size and maxExchange).
  List<String> chooseExchange(GameState state, int seat);

  /// Phase playing: one card string out of `state.legalCards(seat)`.
  String choosePlay(GameState state, int seat);
}

class EasyBot implements Bot {
  final Random _rng;

  EasyBot([Random? rng]) : _rng = rng ?? Random();

  @override
  bool decidePlay(GameState state, int seat) => true;

  @override
  List<String> chooseExchange(GameState state, int seat) => const [];

  @override
  String choosePlay(GameState state, int seat) {
    final legal = state.legalCards(seat);
    return cardString(legal[_rng.nextInt(legal.length)]);
  }
}

class NormalBot implements Bot {
  const NormalBot();

  @override
  bool decidePlay(GameState state, int seat) {
    final trumpSuit = state.trumpSuit;
    var strength = 0;
    for (final c in state.players[seat].hand) {
      if (suitOf(c) == trumpSuit) strength += 2;
      if (rankOf(c) >= 13) strength += 1; // K, A of any suit
    }
    return strength >= 3;
  }

  @override
  List<String> chooseExchange(GameState state, int seat) {
    final p = state.players[seat];
    // Discard weak off-trump cards (below queen), lowest first.
    final weak = p.hand
        .where((c) => suitOf(c) != state.trumpSuit && rankOf(c) < 12)
        .toList()
      ..sort((a, b) => rankOf(a).compareTo(rankOf(b)));
    final limit = min(state.config.maxExchange, state.stock.length);
    return weak.take(limit).map(cardString).toList();
  }

  @override
  String choosePlay(GameState state, int seat) {
    final legal = state.legalCards(seat);
    final trumpSuit = state.trumpSuit;

    // Cheapest card first: low ranks before high, non-trumps before trumps.
    int cost(int c) => (suitOf(c) == trumpSuit ? 100 : 0) + rankOf(c);
    final byCost = [...legal]..sort((a, b) => cost(a).compareTo(cost(b)));

    if (state.trick.isEmpty) {
      // Lead an ace if we have one, otherwise our cheapest card.
      final aces = legal.where((c) => rankOf(c) == 14);
      return cardString(aces.isNotEmpty ? aces.first : byCost.first);
    }

    // Take the trick with the cheapest winning card, else dump the
    // cheapest card.
    final winners = legal.where((c) => _wouldWin(state, c)).toList()
      ..sort((a, b) => cost(a).compareTo(cost(b)));
    return cardString(winners.isNotEmpty ? winners.first : byCost.first);
  }

  /// Whether playing [card] now would beat everything in the current trick.
  /// (Players after us may still beat it.)
  bool _wouldWin(GameState state, int card) {
    final trumpSuit = state.trumpSuit;
    final lead = suitOf(state.trick.first.card);
    int? topTrump;
    var topLead = 0;
    for (final t in state.trick) {
      if (suitOf(t.card) == trumpSuit) {
        if (topTrump == null || rankOf(t.card) > topTrump) {
          topTrump = rankOf(t.card);
        }
      } else if (suitOf(t.card) == lead && rankOf(t.card) > topLead) {
        topLead = rankOf(t.card);
      }
    }
    if (suitOf(card) == trumpSuit) {
      return topTrump == null || rankOf(card) > topTrump;
    }
    return topTrump == null && suitOf(card) == lead && rankOf(card) > topLead;
  }
}
