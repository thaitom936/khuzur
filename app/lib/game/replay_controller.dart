/// Replay playback: re-runs a recorded game through the local rules
/// engine, one action at a time. Read-only towards the table UI.
library;

import 'dart:async';

import '../rules/card.dart';
import '../rules/rules.dart';
import 'game_controller.dart';

class ReplayController extends GameController {
  final Map<String, dynamic> record;

  /// Seat of the viewing player in this match, or -1 (hand hidden).
  int mySeat = -1;

  late GameState state;
  int roundIdx = 0;
  int actionIdx = 0; // number of actions of this round already applied
  bool autoPlay = false;
  Timer? _timer;

  /// Set when a recorded action is rejected by the Dart engine — that
  /// would mean the two engines disagree and is worth reporting.
  String? desyncError;

  ReplayController(this.record, {int? viewerUid}) {
    // seat_uids has one entry per seat (0 for bots).
    final seatUids = (record['seat_uids'] as List? ?? []).cast<int>();
    if (viewerUid != null) {
      mySeat = seatUids.indexOf(viewerUid);
    }
    _loadRound(0, 0);
  }

  List<Map<String, dynamic>> get _rounds =>
      (record['rounds'] as List).cast<Map<String, dynamic>>();

  Map<String, dynamic> get _round => _rounds[roundIdx];

  List<Map<String, dynamic>> get _actions =>
      (_round['actions'] as List).cast<Map<String, dynamic>>();

  bool get atEnd =>
      roundIdx == _rounds.length - 1 && actionIdx == _actions.length;

  void _loadRound(int index, int upTo) {
    roundIdx = index;
    final r = _rounds[index];
    state = GameState.newRound(
      hands: [for (final h in r['hands'] as List) (h as List).cast<String>()],
      trump: r['trump'] as String,
      stock: (r['stock'] as List? ?? []).cast<String>(),
      dealer: r['dealer'] as int,
      config: RuleConfig.fromJson(
          (record['config'] as Map?)?.cast<String, dynamic>() ?? const {}),
      scores: (r['scores'] as List).cast<int>(),
    );
    actionIdx = 0;
    completedTrick = null;
    completedTrickWinner = null;
    for (var i = 0; i < upTo; i++) {
      _applyNext(silent: true);
    }
  }

  void _applyNext({bool silent = false}) {
    final a = _actions[actionIdx];
    final seat = a['s'] as int;
    String? err;
    switch (a['c'] as String) {
      case 'd':
        err = state.decide(seat, a['v'] == true);
      case 'k':
        err = state.takeTrump(seat, a['v'] as String);
      case 'n':
        err = state.skipNavsh(seat);
      case 'e':
        err = state.exchange(seat, (a['v'] as List? ?? []).cast<String>());
      case 'p':
        final playCount =
            state.players.where((p) => p.decision == Decision.play).length;
        final completing = state.trick.length == playCount - 1;
        final before = [...state.trick];
        final tricksBefore = [for (final p in state.players) p.tricks];
        err = state.play(seat, a['v'] as String);
        if (err == null && completing && !silent) {
          completedTrick = [...before, TrickCard(seat, parseCard(a['v'] as String))];
          for (var s = 0; s < state.numPlayers; s++) {
            if (state.players[s].tricks > tricksBefore[s]) {
              completedTrickWinner = s;
            }
          }
        } else if (!silent) {
          completedTrick = null;
          completedTrickWinner = null;
        }
      default:
        err = 'bad_action';
    }
    if (err != null) {
      desyncError = '${a['c']}@$roundIdx:$actionIdx: $err';
      autoPlay = false;
      _timer?.cancel();
    }
    actionIdx++;
  }

  void stepForward() {
    if (desyncError != null) return;
    if (actionIdx < _actions.length) {
      _applyNext();
    } else if (roundIdx + 1 < _rounds.length) {
      _loadRound(roundIdx + 1, 0);
    } else {
      autoPlay = false;
      _timer?.cancel();
    }
    notifyListeners();
  }

  void stepBack() {
    if (actionIdx > 1) {
      _loadRound(roundIdx, actionIdx - 1);
    } else if (actionIdx == 1) {
      _loadRound(roundIdx, 0);
    } else if (roundIdx > 0) {
      _loadRound(roundIdx - 1, 0);
    }
    desyncError = null;
    notifyListeners();
  }

  void toggleAuto() {
    autoPlay = !autoPlay;
    _timer?.cancel();
    if (autoPlay) {
      _timer = Timer.periodic(const Duration(milliseconds: 900), (_) {
        if (atEnd || desyncError != null) {
          autoPlay = false;
          _timer?.cancel();
        } else {
          stepForward();
          return;
        }
        notifyListeners();
      });
    }
    notifyListeners();
  }

  // ---- GameController surface (read-only) ----

  @override
  int get humanSeat => mySeat;
  @override
  int get numPlayers => state.numPlayers;
  @override
  int get roundNo => roundIdx + 1;
  @override
  int get dealer => _round['dealer'] as int;
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
  List<int> get hand =>
      mySeat >= 0 && mySeat < state.numPlayers ? state.players[mySeat].hand : const [];
  @override
  List<int> legalCards() => const [];
  @override
  bool get humanTurn => false;
  @override
  bool get passAllowed => false;
  @override
  int get maxExchangeNow => 0;
  @override
  List<int>? get winners => state.winners;
  @override
  List<TrickCard>? completedTrick;
  @override
  int? completedTrickWinner;
  @override
  DateTime? get turnDeadline => null;
  @override
  bool get isLocal => false;
  @override
  String? get roomCode => null;
  @override
  Map<int, int> get chatBubbles => const {};
  @override
  bool get autoPlaying => false;

  @override
  List<SeatView> get seats {
    final names = (record['names'] as List? ?? []).cast<String>();
    return [
      for (var s = 0; s < state.numPlayers; s++)
        SeatView(
          name: s < names.length ? names[s] : '?',
          score: state.players[s].score,
          tricks: state.players[s].tricks,
          decision: state.players[s].decision,
        ),
    ];
  }

  @override
  void decide(bool play) {}
  @override
  void exchange(List<String> cards) {}
  @override
  void play(String card) {}

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
