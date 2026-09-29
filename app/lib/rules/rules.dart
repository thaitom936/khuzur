/// Muushig rules engine (pure Dart, no Flutter dependency).
///
/// Mirrors `server/lualib/rules/engine.lua`; both implementations are kept
/// in sync by the shared cases in `testdata/rules/`.
///
/// Seats are 0-based. Mutating calls return `null` on success or a stable
/// error id (the state is left unchanged on error).
library;

import 'card.dart';

class RuleConfig {
  final int startScore;
  final int noTrickPenalty;
  final bool mustFollowSuit;
  final bool mustBeat;
  final bool mustTrump;
  final bool mustOvertrump;
  final int mustPlayAtScore;
  final int minPlayers;
  final bool dealerTakesTrump;
  final int maxExchange;

  const RuleConfig({
    this.startScore = 15,
    this.noTrickPenalty = 5,
    this.mustFollowSuit = true,
    this.mustBeat = true,
    this.mustTrump = true,
    this.mustOvertrump = true,
    this.mustPlayAtScore = 1,
    this.minPlayers = 2,
    this.dealerTakesTrump = false,
    this.maxExchange = 5,
  });

  factory RuleConfig.fromJson(Map<String, dynamic> json) {
    const def = RuleConfig();
    return RuleConfig(
      startScore: json['startScore'] as int? ?? def.startScore,
      noTrickPenalty: json['noTrickPenalty'] as int? ?? def.noTrickPenalty,
      mustFollowSuit: json['mustFollowSuit'] as bool? ?? def.mustFollowSuit,
      mustBeat: json['mustBeat'] as bool? ?? def.mustBeat,
      mustTrump: json['mustTrump'] as bool? ?? def.mustTrump,
      mustOvertrump: json['mustOvertrump'] as bool? ?? def.mustOvertrump,
      mustPlayAtScore: json['mustPlayAtScore'] as int? ?? def.mustPlayAtScore,
      minPlayers: json['minPlayers'] as int? ?? def.minPlayers,
      dealerTakesTrump: json['dealerTakesTrump'] as bool? ?? def.dealerTakesTrump,
      maxExchange: json['maxExchange'] as int? ?? def.maxExchange,
    );
  }
}

enum Phase { deciding, exchanging, playing, roundEnd, gameEnd }

enum Decision { none, play, pass }

class PlayerState {
  final List<int> hand;
  int score;
  Decision decision = Decision.none;
  int tricks = 0;
  bool exchanged = false;

  PlayerState(this.hand, this.score);
}

class TrickCard {
  final int seat;
  final int card;

  TrickCard(this.seat, this.card);
}

/// Legal cards to play given a hand and the current trick. Standalone so
/// the online client can compute it from its own view of the table.
List<int> legalCardsFor(
    RuleConfig config, int trumpSuit, List<TrickCard> trick, List<int> hand) {
  List<int> result;

  if (trick.isEmpty) {
    result = hand;
  } else {
    final lead = suitOf(trick.first.card);
    int? topTrump;
    for (final t in trick) {
      if (suitOf(t.card) == trumpSuit &&
          (topTrump == null || rankOf(t.card) > rankOf(topTrump))) {
        topTrump = t.card;
      }
    }
    final followers = hand.where((c) => suitOf(c) == lead).toList();
    final trumps = hand.where((c) => suitOf(c) == trumpSuit).toList();

    if (config.mustFollowSuit && followers.isNotEmpty) {
      result = followers;
      if (config.mustBeat) {
        // The card to beat within the lead suit: irrelevant if the trick has
        // already been trumped by another suit (a lead-suit card can't win).
        int? toBeat;
        if (lead == trumpSuit) {
          toBeat = topTrump;
        } else if (topTrump == null) {
          for (final t in trick) {
            if (suitOf(t.card) == lead &&
                (toBeat == null || rankOf(t.card) > rankOf(toBeat))) {
              toBeat = t.card;
            }
          }
        }
        if (toBeat != null) {
          final limit = rankOf(toBeat);
          final beaters = followers.where((c) => rankOf(c) > limit).toList();
          if (beaters.isNotEmpty) result = beaters;
        }
      }
    } else if (config.mustTrump && trumps.isNotEmpty) {
      result = trumps;
      if (config.mustOvertrump && topTrump != null) {
        final limit = rankOf(topTrump);
        final over = trumps.where((c) => rankOf(c) > limit).toList();
        if (over.isNotEmpty) result = over;
      }
    } else {
      result = hand;
    }
  }
  return [...result]..sort();
}

class GameState {
  final RuleConfig config;
  final int numPlayers;
  final int dealer;
  final List<PlayerState> players;
  final int trumpCard;
  final List<int> stock;

  Phase phase = Phase.deciding;
  int turn;
  List<TrickCard> trick = [];
  int trickNo = 0;
  List<int>? winners;

  int get trumpSuit => suitOf(trumpCard);

  GameState._({
    required this.config,
    required this.numPlayers,
    required this.dealer,
    required this.players,
    required this.trumpCard,
    required this.stock,
  }) : turn = (dealer + 1) % numPlayers;

  /// Creates the state for one round from explicit cards (card strings).
  factory GameState.newRound({
    required List<List<String>> hands,
    required String trump,
    List<String> stock = const [],
    int dealer = 0,
    RuleConfig config = const RuleConfig(),
    List<int>? scores,
  }) {
    final n = hands.length;
    if (n < 2 || n > 5) throw ArgumentError('players must be 2..5');

    final trumpCard = parseCard(trump);
    final seen = <int>{trumpCard};
    List<int> parseAll(List<String> cards) {
      final out = <int>[];
      for (final s in cards) {
        final c = parseCard(s);
        if (!seen.add(c)) throw ArgumentError('duplicate card: $s');
        out.add(c);
      }
      return out;
    }

    final players = <PlayerState>[];
    for (var seat = 0; seat < n; seat++) {
      final hand = parseAll(hands[seat]);
      if (hand.length != 5) throw ArgumentError('each hand must have 5 cards');
      players.add(PlayerState(hand, scores?[seat] ?? config.startScore));
    }
    return GameState._(
      config: config,
      numPlayers: n,
      dealer: dealer,
      players: players,
      trumpCard: trumpCard,
      stock: parseAll(stock),
    );
  }

  int _nextSeat(int seat) => (seat + 1) % numPlayers;

  /// First seat matching [pred], scanning clockwise from [start] inclusive.
  int? _findSeat(int start, bool Function(PlayerState) pred) {
    var s = start;
    for (var i = 0; i < numPlayers; i++) {
      if (pred(players[s])) return s;
      s = _nextSeat(s);
    }
    return null;
  }

  int get _playCount => players.where((p) => p.decision == Decision.play).length;

  String? _checkTurn(Phase phase, int seat) {
    if (this.phase != phase) return 'wrong_phase';
    if (turn != seat) return 'not_your_turn';
    return null;
  }

  /// Phase [Phase.deciding]: choose to play (true) or pass (false).
  String? decide(int seat, bool play) {
    final err = _checkTurn(Phase.deciding, seat);
    if (err != null) return err;
    final p = players[seat];

    if (!play) {
      if (p.score <= config.mustPlayAtScore) return 'must_play_low_score';
      final undecidedAfter =
          players.where((q) => q.decision == Decision.none).length - 1;
      if (_playCount + undecidedAfter < config.minPlayers) {
        return 'must_play_min_players';
      }
    }
    p.decision = play ? Decision.play : Decision.pass;

    final next = _findSeat(_nextSeat(seat), (q) => q.decision == Decision.none);
    if (next != null) {
      turn = next;
    } else if (_playCount == 0) {
      phase = Phase.roundEnd; // everyone passed (only possible when minPlayers == 0)
    } else {
      phase = Phase.exchanging;
      turn = _findSeat(_nextSeat(dealer), (q) => q.decision == Decision.play)!;
    }
    return null;
  }

  /// Phase [Phase.exchanging]: discard [cards] (card strings, may be empty)
  /// and draw the same number from the stock.
  String? exchange(int seat, List<String> cards) {
    final err = _checkTurn(Phase.exchanging, seat);
    if (err != null) return err;
    final p = players[seat];

    if (cards.length > config.maxExchange || cards.length > stock.length) {
      return 'exchange_too_many';
    }
    // Validate before mutating (duplicates in the request also fail here).
    final picked = <int>{};
    for (final s in cards) {
      final c = parseCard(s);
      if (!picked.add(c) || !p.hand.contains(c)) return 'card_not_in_hand';
    }
    p.hand.removeWhere(picked.contains);
    for (var i = 0; i < cards.length; i++) {
      p.hand.add(stock.removeAt(0));
    }
    p.exchanged = true;

    final next = _findSeat(
        _nextSeat(seat), (q) => q.decision == Decision.play && !q.exchanged);
    if (next != null) {
      turn = next;
    } else {
      phase = Phase.playing;
      trickNo = 1;
      trick = [];
      turn = _findSeat(_nextSeat(dealer), (q) => q.decision == Decision.play)!;
    }
    return null;
  }

  /// Highest trump in the current trick, or null.
  int? get _trickTrump {
    int? best;
    for (final t in trick) {
      if (suitOf(t.card) == trumpSuit &&
          (best == null || rankOf(t.card) > rankOf(best))) {
        best = t.card;
      }
    }
    return best;
  }

  /// Legal cards for [seat] in phase [Phase.playing], sorted by card value.
  List<int> legalCards(int seat) =>
      legalCardsFor(config, trumpSuit, trick, players[seat].hand);

  int get _trickWinner {
    final lead = suitOf(trick.first.card);
    final ref = _trickTrump != null ? trumpSuit : lead;
    late int bestSeat;
    int? bestRank;
    for (final t in trick) {
      if (suitOf(t.card) == ref && (bestRank == null || rankOf(t.card) > bestRank)) {
        bestSeat = t.seat;
        bestRank = rankOf(t.card);
      }
    }
    return bestSeat;
  }

  void _settle() {
    for (final p in players) {
      if (p.decision == Decision.play) {
        p.score += p.tricks > 0 ? -p.tricks : config.noTrickPenalty;
      }
    }
    phase = Phase.roundEnd;
    if (players.any((p) => p.score <= 0)) {
      phase = Phase.gameEnd;
      final min = players.map((p) => p.score).reduce((a, b) => a < b ? a : b);
      winners = [
        for (var seat = 0; seat < numPlayers; seat++)
          if (players[seat].score == min) seat,
      ];
    }
  }

  /// Phase [Phase.playing]: play one card (card string).
  String? play(int seat, String cardStr) {
    final err = _checkTurn(Phase.playing, seat);
    if (err != null) return err;
    final p = players[seat];
    final card = parseCard(cardStr);

    if (!p.hand.contains(card)) return 'card_not_in_hand';
    if (!legalCards(seat).contains(card)) return 'illegal_card';

    p.hand.remove(card);
    trick.add(TrickCard(seat, card));

    if (trick.length == _playCount) {
      final winner = _trickWinner;
      players[winner].tricks++;
      if (trickNo == 5) {
        _settle();
      } else {
        trickNo++;
        trick = [];
        turn = winner;
      }
    } else {
      turn = _findSeat(_nextSeat(seat), (q) => q.decision == Decision.play)!;
    }
    return null;
  }
}
