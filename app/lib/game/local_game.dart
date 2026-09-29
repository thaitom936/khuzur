/// Controller for a single-player match against bots.
///
/// Owns the match state across rounds (scores, dealer rotation), runs the
/// bot turns with small delays, and exposes everything the table UI needs.
/// A later RemoteGameController will expose the same surface backed by the
/// server instead.
library;

import 'dart:async';
import 'dart:math';

import '../bot/bot.dart';
import '../rules/card.dart';
import '../rules/deal.dart';
import '../rules/rules.dart';
import 'game_controller.dart';

class LocalGameController extends GameController {
  static const botDelay = Duration(milliseconds: 700);
  static const trickPause = Duration(milliseconds: 1100);

  @override
  final int humanSeat = 0;
  @override
  final int numPlayers;
  final RuleConfig config;
  final Bot _bot;
  final Random _rng;

  late GameState state;
  @override
  late int dealer;
  @override
  int roundNo = 1;
  bool _disposed = false;
  bool _botsRunning = false;

  /// The just-completed trick and its winner, kept briefly so the UI can
  /// show it (the engine clears the trick as soon as it completes).
  @override
  List<TrickCard>? completedTrick;
  @override
  int? completedTrickWinner;

  // ---- view surface shared with the remote controller ----

  @override
  Phase get phase => state.phase;
  @override
  int get turn => state.turn;
  @override
  int get trumpCard => state.trumpCard;
  @override
  int get stockCount => state.stock.length;
  @override
  List<TrickCard> get trick => state.trick;
  @override
  List<int> get hand => state.players[humanSeat].hand;
  @override
  List<int> legalCards() => state.legalCards(humanSeat);
  @override
  List<int>? get winners => state.winners;
  @override
  DateTime? get turnDeadline => null;
  @override
  bool get isLocal => true;
  @override
  String? get roomCode => null;
  @override
  Map<int, int> get chatBubbles => const {};
  @override
  bool get autoPlaying => false;

  @override
  List<SeatView> get seats => [
    for (var s = 0; s < numPlayers; s++)
      SeatView(
        name: s == humanSeat ? 'You' : 'Bot $s',
        score: state.players[s].score,
        tricks: state.players[s].tricks,
        decision: state.players[s].decision,
        bot: s != humanSeat,
      ),
  ];

  LocalGameController({
    this.numPlayers = 4,
    this.config = const RuleConfig(),
    Bot? bot,
    Random? random,
  }) : _bot = bot ?? const NormalBot(),
       _rng = random ?? Random.secure() {
    dealer = _rng.nextInt(numPlayers);
    _deal(List.filled(numPlayers, config.startScore));
    _runBots();
  }

  void _deal(List<int> scores) {
    state = deal(
      numPlayers: numPlayers,
      dealer: dealer,
      scores: scores,
      config: config,
      random: _rng,
    );
    tableMotion = TableMotionEvent(TableMotionKind.deal);
  }

  @override
  bool get humanTurn => _phaseActive && state.turn == humanSeat;

  bool get _phaseActive =>
      state.phase == Phase.deciding ||
      state.phase == Phase.exchanging ||
      state.phase == Phase.playing;

  /// Whether the human may pass right now (mirrors the engine's checks so
  /// the UI can disable the button instead of showing an error).
  @override
  bool get passAllowed {
    if (state.players[humanSeat].score <= config.mustPlayAtScore) return false;
    final undecidedAfter =
        state.players.where((p) => p.decision == Decision.none).length - 1;
    final playCount = state.players
        .where((p) => p.decision == Decision.play)
        .length;
    return playCount + undecidedAfter >= config.minPlayers;
  }

  @override
  int get maxExchangeNow => min(config.maxExchange, state.stock.length);

  @override
  void decide(bool play) {
    if (!humanTurn) return;
    if (state.decide(humanSeat, play) == null) {
      notifyListeners();
      _runBots();
    }
  }

  @override
  void exchange(List<String> cards) {
    if (!humanTurn) return;
    if (state.exchange(humanSeat, cards) == null) {
      notifyListeners();
      _runBots();
    }
  }

  @override
  bool get canTakeTrump =>
      humanTurn &&
      state.phase == Phase.exchanging &&
      humanSeat == state.dealer &&
      !state.trumpTaken &&
      config.dealerTakesTrump;

  @override
  void takeTrump(String card) {
    if (!humanTurn) return;
    if (state.takeTrump(humanSeat, card) == null) {
      notifyListeners(); // the turn continues: the dealer still exchanges
    }
  }

  @override
  void play(String card) {
    if (!humanTurn) return;
    if (_playCard(humanSeat, card) == null) {
      notifyListeners();
      _runBots();
    }
  }

  /// Starts the next round after a round_end overlay.
  @override
  void nextRound() {
    assert(state.phase == Phase.roundEnd);
    dealer = (dealer + 1) % numPlayers;
    roundNo++;
    _deal([for (final p in state.players) p.score]);
    completedTrick = null;
    completedTrickWinner = null;
    notifyListeners();
    _runBots();
  }

  /// Plays a card and, when this completes a trick, records it (plus the
  /// winner) for display and schedules the display to clear.
  String? _playCard(int seat, String card) {
    final playCount = state.players
        .where((p) => p.decision == Decision.play)
        .length;
    final completing = state.trick.length == playCount - 1;
    final before = completing ? [...state.trick] : null;
    final tricksBefore = [for (final p in state.players) p.tricks];

    final err = state.play(seat, card);
    if (err == null) {
      tableMotion = TableMotionEvent(
        TableMotionKind.play,
        TrickCard(seat, parseCard(card)),
      );
    }
    if (err == null && completing) {
      completedTrick = [...before!, TrickCard(seat, parseCard(card))];
      for (var s = 0; s < numPlayers; s++) {
        if (state.players[s].tricks > tricksBefore[s]) {
          completedTrickWinner = s;
        }
      }
      _scheduleCollect(completedTrickWinner!);
      Timer(trickPause, () {
        if (_disposed) return;
        completedTrick = null;
        completedTrickWinner = null;
        notifyListeners();
      });
    }
    return err;
  }

  /// After a short look at the full trick, the cards fly to the winner.
  void _scheduleCollect(int winner) {
    Timer(const Duration(milliseconds: 380), () {
      if (_disposed || completedTrickWinner != winner) return;
      tableMotion = TableMotionEvent(TableMotionKind.collect, null, winner);
      notifyListeners();
    });
  }

  Future<void> _runBots() async {
    if (_botsRunning) return;
    _botsRunning = true;
    try {
      while (!_disposed && _phaseActive && !humanTurn) {
        if (completedTrick != null) {
          // Let the finished trick stay on screen before the next play.
          await Future<void>.delayed(trickPause);
        } else {
          await Future<void>.delayed(botDelay);
        }
        if (_disposed || !_phaseActive || humanTurn) break;
        _applyBotAction(state.turn);
        notifyListeners();
      }
    } finally {
      _botsRunning = false;
    }
  }

  void _applyBotAction(int seat) {
    switch (state.phase) {
      case Phase.deciding:
        if (_bot.decidePlay(state, seat)) {
          state.decide(seat, true);
        } else if (state.decide(seat, false) != null) {
          state.decide(seat, true); // passing was illegal, forced to play
        }
      case Phase.exchanging:
        // The dealer bot may first trade a weak card for the face-up trump.
        if (seat == state.dealer && !state.trumpTaken) {
          final give = _bot.chooseTrumpTake(state, seat);
          if (give != null) state.takeTrump(seat, give);
        }
        final cards = _bot.chooseExchange(state, seat);
        if (state.exchange(seat, cards) != null) {
          state.exchange(seat, const []);
        }
      case Phase.playing:
        _playCard(seat, _bot.choosePlay(state, seat));
      case Phase.roundEnd:
      case Phase.gameEnd:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
