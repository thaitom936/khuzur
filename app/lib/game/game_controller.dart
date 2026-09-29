/// The surface the table UI talks to, implemented by both the local
/// (vs bots) and the remote (online) game controllers.
library;

import 'package:flutter/foundation.dart';

import '../rules/card.dart';
import '../rules/rules.dart';

class SeatView {
  final String name;
  final int score;
  final int tricks;
  final Decision decision;
  final bool online;
  final bool auto;
  final bool bot;

  const SeatView({
    required this.name,
    required this.score,
    required this.tricks,
    required this.decision,
    this.online = true,
    this.auto = false,
    this.bot = false,
  });
}

abstract class GameController extends ChangeNotifier {
  /// Presentation events are separate from authoritative rule state. A snapshot
  /// resets motion; ordinary turn/score notifications never replay animations.
  TableMotionEvent? tableMotion;
  List<int> get displayHand => hand;
  List<TrickCard> get displayTrick => completedTrick ?? trick;
  bool get playPending => false;

  int get numPlayers;
  int get humanSeat;
  int get roundNo;
  int get dealer;
  Phase get phase;
  int get turn;
  int get trumpCard;
  int get stockCount;
  List<TrickCard> get trick;
  List<SeatView> get seats;

  /// The human player's cards, unsorted.
  List<int> get hand;

  /// Legal cards on the human's playing turn.
  List<int> legalCards();

  bool get humanTurn;
  bool get passAllowed;
  int get maxExchangeNow;
  List<int>? get winners;

  /// The just-completed trick and its winner, kept briefly for display.
  List<TrickCard>? get completedTrick;
  int? get completedTrickWinner;

  /// When the current turn times out, or null (local play has no clock).
  DateTime? get turnDeadline;

  /// Local games show a "next round" button; online rounds auto-advance.
  bool get isLocal;

  /// Friend-room code, when in one.
  String? get roomCode;

  /// Chat: last phrase id per seat (cleared after a few seconds).
  Map<int, int> get chatBubbles;

  /// Whether this player is in auto-play (online: after timeouts).
  bool get autoPlaying;

  void decide(bool play);
  void exchange(List<String> cards);
  void play(String card);

  /// Dealer privilege: trade [card] for the face-up trump card
  /// (own exchange turn only).
  void takeTrump(String card) {}
  void nextRound() {}
  void sendChat(int phraseId) {}
  void setAuto(bool on) {}

  /// Whether the dealer trade is available to us right now.
  bool get canTakeTrump => false;
}

enum TableMotionKind { deal, play, returnCard, collect, reset }

class TableMotionEvent {
  final TableMotionKind kind;
  final TrickCard? card;

  /// For [TableMotionKind.collect]: the seat the trick flies to.
  final int? seat;

  TableMotionEvent(this.kind, [this.card, this.seat]);
}
