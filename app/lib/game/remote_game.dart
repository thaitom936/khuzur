/// Online game controller: builds the table view from server pushes and
/// sends the player's actions to the server.
library;

import 'dart:async';

import '../net/net_client.dart';
import '../net/session.dart';
import '../rules/card.dart';
import '../rules/rules.dart';
import 'game_controller.dart';

class RemoteGameController extends GameController {
  static const trickPause = Duration(milliseconds: 1100);
  static const chatBubbleTime = Duration(seconds: 4);

  final Session session;
  late final StreamSubscription _sub;

  RemoteGameController(this.session) {
    _sub = session.client.pushes.listen(_onPush);
  }

  // ---- state from pushes ----

  @override
  int humanSeat = 0;
  @override
  int numPlayers = 0;
  @override
  int roundNo = 0;
  @override
  int dealer = 0;
  @override
  Phase phase = Phase.deciding;
  @override
  int turn = -1;
  @override
  int trumpCard = 7;
  @override
  int stockCount = 0;
  @override
  List<TrickCard> trick = [];
  @override
  List<SeatView> seats = [];
  @override
  List<int> hand = [];
  @override
  List<int>? winners;
  @override
  List<TrickCard>? completedTrick;
  @override
  int? completedTrickWinner;
  @override
  DateTime? turnDeadline;
  @override
  String? roomCode;
  @override
  final Map<int, int> chatBubbles = {};
  @override
  bool autoPlaying = false;

  /// Coin winnings by seat, from the game_end push.
  Map<int, int> winnings = {};
  int stake = 0;

  RuleConfig config = const RuleConfig();
  bool started = false;
  bool gameOver = false;

  /// True while the player has intentionally left the table mid-game
  /// (the lobby then offers a "return to game" button instead of
  /// navigating back automatically).
  bool suspended = false;
  bool _canPassNow = false;
  bool _disposed = false;

  @override
  bool get isLocal => false;

  @override
  bool get humanTurn =>
      started &&
      !gameOver &&
      turn == humanSeat &&
      (phase == Phase.deciding ||
          phase == Phase.exchanging ||
          phase == Phase.playing);

  @override
  bool get passAllowed => _canPassNow;

  @override
  int get maxExchangeNow =>
      stockCount < config.maxExchange ? stockCount : config.maxExchange;

  @override
  List<int> legalCards() =>
      legalCardsFor(config, suitOf(trumpCard), trick, hand);

  // ---- actions ----

  void _send(String cmd, [Map<String, dynamic>? args]) {
    session.client.call(cmd, args).catchError((Object e) {
      // The server is authoritative; a rejected action just leaves the
      // table as-is and the turn timer running.
      return <String, dynamic>{};
    });
  }

  @override
  void decide(bool play) => _send('decide', {'play': play});

  @override
  void exchange(List<String> cards) => _send('exchange', {'cards': cards});

  @override
  void play(String card) => _send('play_card', {'card': card});

  @override
  void sendChat(int phraseId) => _send('chat', {'phrase': phraseId});

  @override
  void setAuto(bool on) => _send('auto', {'on': on});

  void leaveRoom() => _send('leave_room');

  /// Clears table state after a finished game, back in the lobby.
  void reset() {
    started = false;
    gameOver = false;
    suspended = false;
    winners = null;
    phase = Phase.deciding;
    turn = -1;
    seats = [];
    hand = [];
    trick = [];
    completedTrick = null;
    completedTrickWinner = null;
    roomCode = null;
    roundNo = 0;
    autoPlaying = false;
    turnDeadline = null;
    winnings = {};
    stake = 0;
    notifyListeners();
  }

  // ---- push handling ----

  static const _phases = {
    'deciding': Phase.deciding,
    'exchanging': Phase.exchanging,
    'playing': Phase.playing,
    'round_end': Phase.roundEnd,
    'game_end': Phase.gameEnd,
  };

  List<SeatView> _parseSeats(List seatList) {
    return [
      for (final s in seatList.cast<Map<String, dynamic>>())
        SeatView(
          name: s['name'] as String? ?? '?',
          score: s['score'] as int? ?? config.startScore,
          tricks: s['tricks'] as int? ?? 0,
          decision: switch (s['decision']) {
            'play' => Decision.play,
            'pass' => Decision.pass,
            _ => Decision.none,
          },
          online: s['online'] as bool? ?? true,
          auto: s['auto'] as bool? ?? false,
          bot: s['bot'] as bool? ?? false,
        ),
    ];
  }

  void _updateSeat(int seat,
      {int? score, int? tricks, Decision? decision, bool? online, bool? auto}) {
    if (seat < 0 || seat >= seats.length) return;
    final s = seats[seat];
    seats[seat] = SeatView(
      name: s.name,
      score: score ?? s.score,
      tricks: tricks ?? s.tricks,
      decision: decision ?? s.decision,
      online: online ?? s.online,
      auto: auto ?? s.auto,
      bot: s.bot,
    );
  }

  void _onPush(Map<String, dynamic> msg) {
    if (_disposed) return;
    switch (msg['push'] as String) {
      case 'game_start' || 'snapshot':
        humanSeat = msg['you'] as int? ?? humanSeat;
        numPlayers = msg['size'] as int? ?? numPlayers;
        roomCode = msg['code'] as String?;
        stake = msg['stake'] as int? ?? 0;
        if (msg['config'] is Map) {
          config = RuleConfig.fromJson((msg['config'] as Map).cast());
        }
        seats = _parseSeats(msg['seats'] as List? ?? []);
        started = msg['started'] as bool? ?? true;
        gameOver = false;
        if (msg['push'] == 'snapshot') {
          roundNo = msg['round'] as int? ?? roundNo;
          phase = _phases[msg['phase']] ?? phase;
          turn = msg['turn'] as int? ?? turn;
          dealer = msg['dealer'] as int? ?? dealer;
          if (msg['trump'] is String) {
            trumpCard = parseCard(msg['trump'] as String);
          }
          stockCount = msg['stock'] as int? ?? 0;
          trick = [
            for (final t in (msg['trick'] as List? ?? []))
              TrickCard(t['seat'] as int, parseCard(t['card'] as String)),
          ];
          hand = [
            for (final c in (msg['hand'] as List? ?? [])) parseCard(c as String),
          ];
          final dl = msg['deadline'] as int?;
          turnDeadline = dl == null
              ? null
              : DateTime.now().add(Duration(milliseconds: dl * 10));
        }
      case 'round_start':
        roundNo = msg['round'] as int;
        dealer = msg['dealer'] as int;
        trumpCard = parseCard(msg['trump'] as String);
        stockCount = msg['stock'] as int;
        hand = [for (final c in msg['hand'] as List) parseCard(c as String)];
        trick = [];
        completedTrick = null;
        completedTrickWinner = null;
        final scoreList = (msg['scores'] as List).cast<int>();
        for (var s = 0; s < scoreList.length; s++) {
          _updateSeat(s, score: scoreList[s], tricks: 0, decision: Decision.none);
        }
      case 'turn':
        turn = msg['seat'] as int;
        phase = _phases[msg['phase']] ?? phase;
        _canPassNow = msg['can_pass'] as bool? ?? true;
        final dl = msg['deadline'] as int? ?? 0;
        turnDeadline = DateTime.now().add(Duration(milliseconds: dl * 10));
      case 'decided':
        _updateSeat(msg['seat'] as int,
            decision: msg['play'] == true ? Decision.play : Decision.pass);
      case 'exchanged':
        final count = msg['count'] as int? ?? 0;
        stockCount = (stockCount - count).clamp(0, 32);
      case 'exchange_result':
        hand = [for (final c in msg['hand'] as List) parseCard(c as String)];
      case 'played':
        final seat = msg['seat'] as int;
        final card = parseCard(msg['card'] as String);
        trick = [...trick, TrickCard(seat, card)];
        if (seat == humanSeat) hand = [...hand]..remove(card);
      case 'trick_end':
        final winner = msg['winner'] as int;
        completedTrick = trick;
        completedTrickWinner = winner;
        trick = [];
        _updateSeat(winner, tricks: seats[winner].tricks + 1);
        Timer(trickPause, () {
          if (_disposed) return;
          completedTrick = null;
          completedTrickWinner = null;
          notifyListeners();
        });
      case 'round_end':
        phase = Phase.roundEnd;
        for (final r in (msg['results'] as List).cast<Map<String, dynamic>>()) {
          _updateSeat(r['seat'] as int,
              score: r['score'] as int, tricks: r['tricks'] as int);
        }
      case 'game_end':
        phase = Phase.gameEnd;
        gameOver = true;
        winners = (msg['winners'] as List).cast<int>();
        winnings = {
          for (final w
              in (msg['winnings'] as List? ?? []).cast<Map<String, dynamic>>())
            w['seat'] as int: w['coins'] as int,
        };
      case 'seat_state':
        final seat = msg['seat'] as int;
        _updateSeat(seat,
            online: msg['online'] as bool?, auto: msg['auto'] as bool?);
        if (seat == humanSeat) autoPlaying = msg['auto'] == true;
      case 'chat':
        final seat = msg['seat'] as int;
        chatBubbles[seat] = msg['phrase'] as int? ?? 0;
        Timer(chatBubbleTime, () {
          if (_disposed) return;
          chatBubbles.remove(seat);
          notifyListeners();
        });
      case 'room_update':
        roomCode = msg['code'] as String?;
        numPlayers = msg['size'] as int? ?? numPlayers;
        stake = msg['stake'] as int? ?? stake;
        seats = _parseSeats(msg['seats'] as List? ?? []);
        started = false;
      default:
        return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub.cancel();
    super.dispose();
  }
}
