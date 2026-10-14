/// Online game controller: builds the table view from server pushes and
/// sends the player's actions to the server.
library;

import 'dart:async';

import '../net/net_client.dart';
import '../net/session.dart';
import '../rules/card.dart';
import '../rules/durak.dart';
import '../rules/mongol13.dart';
import '../rules/rules.dart';
import '../rules/thousand.dart';
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
  bool locked = false;
  String gameType = 'muushig';
  @override
  bool get isMongol13 => gameType == 'mongol13';
  @override
  bool get isDurak => gameType == 'durak';
  @override
  bool get isThousand => gameType == 'thousand';
  Map<String, dynamic> thousand = {};
  Map<String, dynamic>? _pendingThousandAction;
  String get thousandStage => thousand['stage'] as String? ?? 'bid';
  int get thousandBid => thousand['bid'] as int? ?? 100;
  int get thousandContract => thousand['contract'] as int? ?? 100;
  int get thousandBidder => thousand['bidder'] as int? ?? 0;
  bool canAnnounceThousand(int card) =>
      humanSeat >= 0 &&
      humanSeat < seats.length &&
      thousandCanAnnounce(hand, trick, seats[humanSeat].tricks, card);
  Future<void> thousandAction(
    String action, {
    Object? value,
    bool announce = false,
  }) async {
    if (!isThousand || !humanTurn) return;
    final request = <String, dynamic>{
      'action': action,
      'value': value,
      'announce': announce,
    };
    _pendingThousandAction = request;
    _pendingCombo = [];
    TrickCard? pending;
    if (action == 'play' && value is String) {
      _pendingCombo = null;
      pending = TrickCard(humanSeat, parseCard(value));
      _pendingPlay = pending;
      tableMotion = TableMotionEvent(TableMotionKind.play, pending);
    }
    playError = null;
    notifyListeners();
    try {
      await session.client.call('thousand_action', request);
    } catch (error) {
      if (_disposed || !identical(_pendingThousandAction, request)) return;
      _pendingThousandAction = null;
      _pendingCombo = null;
      _pendingPlay = null;
      playError = error is NetException ? error.code : 'generic';
      playErrorVersion++;
      if (pending != null) {
        tableMotion = TableMotionEvent(TableMotionKind.returnCard, pending);
      }
      notifyListeners();
    }
  }

  Map<String, dynamic> durak = {};
  Map<String, dynamic>? _pendingDurakAction;
  bool drawn = false;
  bool restarting = false;
  Future<void> restartDurak() async {
    if (restarting || !(isDurak || isThousand) || !gameOver || humanSeat != 0) {
      return;
    }
    restarting = true;
    notifyListeners();
    try {
      await session.client.call('start_room');
    } catch (error) {
      if (!_disposed) {
        playError = error is NetException ? error.code : 'generic';
        playErrorVersion++;
      }
    } finally {
      restarting = false;
      if (!_disposed) notifyListeners();
    }
  }

  String get durakStage => durak['stage'] as String? ?? 'attack';
  int get durakLimit => durak['limit'] as int? ?? 5;
  List<DurakPair> get durakPairs => [
    for (final p in durak['pairs'] as List? ?? [])
      DurakPair(
        parseCard(p['attack'] as String),
        p['attack_seat'] as int,
        p['cover'] is String ? parseCard(p['cover'] as String) : null,
        p['cover_seat'] as int?,
      ),
  ];
  List<DurakPair> get displayDurakPairs {
    final pairs = [...durakPairs];
    final action = _pendingDurakAction;
    if (action != null) {
      final cards = _pendingCombo ?? [];
      if (action['action'] == 'defend' && cards.isNotEmpty) {
        final target = action['target'] as int;
        if (target >= 0 && target < pairs.length) {
          pairs[target] = DurakPair(
            pairs[target].attack,
            pairs[target].attacker,
            cards.first.card,
            humanSeat,
          );
        }
      } else if (action['action'] == 'attack' ||
          action['action'] == 'transfer') {
        pairs.addAll(cards.map((c) => DurakPair(c.card, humanSeat)));
      }
    }
    return pairs;
  }

  DurakHint durakSuggestion() {
    final def = durak['defender'] as int? ?? 0;
    var next = (def + 1) % numPlayers;
    for (var i = 0; i < numPlayers && seats[next].finished; i++) {
      next = (next + 1) % numPlayers;
    }
    return durakHint(
      hand,
      durakPairs,
      durakStage,
      trumpSuit,
      durakLimit,
      durak['transfer'] == true,
      seats[next].handCount,
      durak['max_attacks'] as int? ?? 5,
    );
  }

  Future<void> durakAction(
    String action, {
    List<int> cards = const [],
    int? target,
  }) async {
    if (!isDurak || !humanTurn || !cards.every(hand.contains)) return;
    final pending = cards.map((c) => TrickCard(humanSeat, c)).toList();
    final request = <String, dynamic>{
      'action': action,
      'cards': cards.map(cardString).toList(),
      'target': ?target,
    };
    _pendingDurakAction = request;
    _pendingCombo = pending;
    playError = null;
    if (pending.isNotEmpty) {
      tableMotion = TableMotionEvent(TableMotionKind.play, null, null, pending);
    }
    notifyListeners();
    try {
      await session.client.call('durak_action', request);
    } catch (error) {
      if (_disposed || !identical(_pendingDurakAction, request)) return;
      _pendingDurakAction = null;
      _pendingCombo = null;
      playError = error is NetException ? error.code : 'generic';
      playErrorVersion++;
      if (pending.isNotEmpty) {
        tableMotion = TableMotionEvent(
          TableMotionKind.returnCard,
          null,
          null,
          pending,
        );
      }
      notifyListeners();
    }
  }

  @override
  int? openingCard;
  bool dragon = false;
  List<TrickCard>? _pendingCombo;
  Map<String, dynamic> rtc = {};
  bool get rtcEnabled => rtc['enabled'] == true;
  int get rtcPayer => rtc['payer_uid'] as int? ?? 0;
  int get rtcVideoEpoch => rtc['video_epoch'] as int? ?? 0;

  void updateRtc(Map<String, dynamic> state) {
    rtc = Map.of(state);
    notifyListeners();
  }

  @override
  bool trumpTaken = false;

  /// Fixed at the deal; the dealer's trade never changes the trump suit.
  @override
  int trumpSuit = 2;

  /// True when watching someone else's game (snapshot with you = -1).
  bool get spectating => humanSeat < 0;

  bool get canTakeSeat =>
      spectating && !gameOver && !started && seats.length < numPlayers;

  Future<void> takeSeat() async {
    if (!canTakeSeat || roomCode == null) throw NetException('room_full');
    await session.client.call('join_room', {'code': roomCode});
  }

  void unwatch() {
    _send('unwatch');
    reset();
  }

  RuleConfig config = const RuleConfig();
  bool started = false;
  bool gameOver = false;

  /// True while the player has intentionally left the table mid-game
  /// (the lobby then offers a "return to game" button instead of
  /// navigating back automatically).
  bool suspended = false;
  bool _canPassNow = false;
  bool _disposed = false;
  TrickCard? _pendingPlay;
  bool _awaitingPlayTurn = false;
  String? playError;
  int playErrorVersion = 0;

  @override
  bool get playPending =>
      _pendingPlay != null || _pendingCombo != null || _awaitingPlayTurn;

  @override
  List<int> get displayHand => [
    for (final card in hand)
      if (card != _pendingPlay?.card &&
          !(_pendingCombo?.any((t) => t.card == card) ?? false))
        card,
  ];

  @override
  List<TrickCard> get displayTrick => isDurak
      ? [
          for (final p in displayDurakPairs) ...[
            TrickCard(p.attacker, p.attack),
            if (p.cover != null) TrickCard(p.defender ?? 0, p.cover!),
          ],
        ]
      : _pendingCombo ??
            [
              ...(_pendingPlay == null ? super.displayTrick : trick),
              ?_pendingPlay,
            ];

  void _resetMotion() {
    _pendingDurakAction = null;
    _pendingThousandAction = null;
    _pendingCombo = null;
    _pendingPlay = null;
    _awaitingPlayTurn = false;
    playError = null;
    tableMotion = TableMotionEvent(TableMotionKind.reset);
  }

  @override
  bool get isLocal => false;

  @override
  bool get humanTurn =>
      started &&
      !gameOver &&
      !playPending &&
      turn == humanSeat &&
      (phase == Phase.deciding ||
          phase == Phase.exchanging ||
          phase == Phase.navsh ||
          phase == Phase.playing);

  @override
  bool get passAllowed => _canPassNow;

  @override
  int get maxExchangeNow => isThousand
      ? (thousandStage == 'give' ? 2 : 0)
      : stockCount < config.maxExchange
      ? stockCount
      : config.maxExchange;

  @override
  List<int> legalCards() => isThousand
      ? thousandLegalCards(hand, trick, trumpSuit)
      : isMongol13 || isDurak
      ? [...hand]
      : legalCardsFor(config, trumpSuit, trick, hand);

  List<int> comboHint() =>
      m13Hint(hand, trick.map((t) => t.card).toList(), openingCard);
  bool validCombo(List<int> cards) =>
      m13CanPlay(hand, cards, trick.map((t) => t.card).toList(), openingCard);
  Future<void> playCombo(List<int> cards) async {
    if (!humanTurn ||
        !isMongol13 ||
        cards.isEmpty ||
        !cards.every(hand.contains)) {
      return;
    }
    final pending = cards.map((c) => TrickCard(humanSeat, c)).toList();
    _pendingCombo = pending;
    playError = null;
    tableMotion = TableMotionEvent(TableMotionKind.play, null, null, pending);
    notifyListeners();
    try {
      await session.client.call('play_card', {
        'cards': cards.map(cardString).toList(),
      });
    } catch (error) {
      if (_disposed || !identical(_pendingCombo, pending)) return;
      _pendingCombo = null;
      playError = error is NetException ? error.code : 'generic';
      playErrorVersion++;
      tableMotion = TableMotionEvent(
        TableMotionKind.returnCard,
        null,
        null,
        pending,
      );
      notifyListeners();
    }
  }

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
  void play(String card) {
    if (!humanTurn || phase != Phase.playing) return;
    final value = parseCard(card);
    if (!hand.contains(value)) return;
    final pending = TrickCard(humanSeat, value);
    _pendingPlay = pending;
    playError = null;
    tableMotion = TableMotionEvent(TableMotionKind.play, pending);
    notifyListeners(); // Render immediately; the request never blocks motion.
    _submitPlay(card, pending);
  }

  Future<void> _submitPlay(String card, TrickCard pending) async {
    try {
      await session.client.call('play_card', {'card': card});
      // The played push commits state. An ACK alone must not add a second card.
    } catch (error) {
      if (_disposed || !identical(_pendingPlay, pending)) return;
      _pendingPlay = null;
      playError = error is NetException ? error.code : 'generic';
      playErrorVersion++;
      tableMotion = TableMotionEvent(TableMotionKind.returnCard, pending);
      notifyListeners();
    }
  }

  @override
  void takeTrump(String card) => _send('take_trump', {'card': card});

  @override
  bool get canTakeTrump => humanTurn && phase == Phase.navsh;

  @override
  void skipNavsh() => _send('skip_navsh');

  @override
  void sendChat(int phraseId) => _send('chat', {'phrase': phraseId});

  @override
  void setAuto(bool on) => _send('auto', {'on': on});

  void leaveRoom() {
    _send('leave_room');
    reset();
  }

  /// Mid-game forfeit: the seat goes to a bot, the loss is recorded and
  /// this player is immediately free to join another game.
  void abandon() {
    _send('leave_room');
    reset();
  }

  /// Clears table state after a finished game, back in the lobby.
  void reset() {
    restarting = false;
    durak = {};
    thousand = {};
    drawn = false;
    gameType = 'muushig';
    openingCard = null;
    dragon = false;
    rtc = {};
    _resetMotion();
    humanSeat = 0;
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
    locked = false;
    notifyListeners();
  }

  // ---- push handling ----

  static const _phases = {
    'deciding': Phase.deciding,
    'exchanging': Phase.exchanging,
    'navsh': Phase.navsh,
    'playing': Phase.playing,
    'round_end': Phase.roundEnd,
    'game_end': Phase.gameEnd,
  };

  List<SeatView> _parseSeats(List seatList) {
    return [
      for (final s in seatList.cast<Map<String, dynamic>>())
        SeatView(
          name: s['name'] as String? ?? '?',
          rtcUid: s['rtc_uid'] as int?,
          handCount: s['hand'] as int? ?? 0,
          finished: s['finished'] == true,
          score: s['score'] as int? ?? config.startScore,
          tricks: s['tricks'] as int? ?? 0,
          wonCards: [
            for (final card
                in s['won_cards'] is List ? s['won_cards'] as List : const [])
              parseCard(card as String),
          ],
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

  void _updateSeat(
    int seat, {
    int? score,
    int? tricks,
    List<int>? wonCards,
    Decision? decision,
    bool? online,
    bool? auto,
  }) {
    if (seat < 0 || seat >= seats.length) return;
    final s = seats[seat];
    seats[seat] = SeatView(
      name: s.name,
      rtcUid: s.rtcUid,
      handCount: s.handCount,
      finished: s.finished,
      score: score ?? s.score,
      tricks: tricks ?? s.tricks,
      wonCards: wonCards ?? s.wonCards,
      decision: decision ?? s.decision,
      online: online ?? s.online,
      auto: auto ?? s.auto,
      bot: s.bot,
    );
  }

  void _onPush(Map<String, dynamic> msg) {
    if (_disposed) return;
    if (msg['push'] == 'rtc_state' && msg['code'] != roomCode) return;
    if (msg['game_type'] is String) gameType = msg['game_type'] as String;
    if (msg['thousand'] is Map) {
      thousand = Map<String, dynamic>.from(msg['thousand'] as Map);
    }
    if (msg['durak'] is Map) {
      durak = Map<String, dynamic>.from(msg['durak'] as Map);
    }
    if (msg['m13'] is Map) {
      final m = msg['m13'] as Map;
      openingCard = m['opening'] is String
          ? parseCard(m['opening'] as String)
          : null;
      dragon = m['dragon'] == true;
    }
    if (msg['rtc'] is Map) rtc = Map<String, dynamic>.from(msg['rtc'] as Map);
    switch (msg['push'] as String) {
      case 'rtc_state':
        break;
      case 'thousand_state':
        _pendingThousandAction = null;
        _pendingCombo = null;
        _pendingPlay = null;
        _awaitingPlayTurn = false;
        humanSeat = msg['you'] as int? ?? humanSeat;
        numPlayers = msg['size'] as int? ?? numPlayers;
        seats = _parseSeats(msg['seats'] as List? ?? []);
        hand = [
          for (final c in msg['hand'] as List? ?? []) parseCard(c as String),
        ];
        trick = [
          for (final t in msg['trick'] as List? ?? [])
            TrickCard(t['seat'] as int, parseCard(t['card'] as String)),
        ];
        phase = _phases[msg['phase']] ?? phase;
        turn = msg['turn'] as int? ?? turn;
        trumpSuit = msg['trump_suit'] as int? ?? -1;
        stockCount = msg['stock'] as int? ?? 0;
        _canPassNow = msg['can_pass'] == true;
        if (msg['trump'] is String) {
          trumpCard = parseCard(msg['trump'] as String);
        }
      case 'durak_state':
        final predicted =
            _pendingDurakAction != null && msg['action_seat'] == humanSeat;
        _pendingDurakAction = null;
        _pendingCombo = null;
        _awaitingPlayTurn = false;
        humanSeat = msg['you'] as int? ?? humanSeat;
        numPlayers = msg['size'] as int? ?? numPlayers;
        seats = _parseSeats(msg['seats'] as List? ?? []);
        hand = [
          for (final c in msg['hand'] as List? ?? []) parseCard(c as String),
        ];
        phase = _phases[msg['phase']] ?? phase;
        turn = msg['turn'] as int? ?? turn;
        stockCount = msg['stock'] as int? ?? stockCount;
        if (msg['trump'] is String) {
          trumpCard = parseCard(msg['trump'] as String);
        }
        trumpSuit = msg['trump_suit'] as int? ?? trumpSuit;
        _canPassNow = msg['can_pass'] == true;
        if (!predicted && (msg['cards'] as List? ?? []).isNotEmpty) {
          tableMotion = TableMotionEvent(TableMotionKind.play, null, null, [
            for (final c in msg['cards'] as List)
              TrickCard(msg['action_seat'] as int, parseCard(c as String)),
          ]);
        }
      case 'm13_state':
        final predicted =
            _pendingCombo != null && msg['action_seat'] == humanSeat;
        _pendingCombo = null;
        _awaitingPlayTurn = false;
        humanSeat = msg['you'] as int? ?? humanSeat;
        numPlayers = msg['size'] as int? ?? numPlayers;
        seats = _parseSeats(msg['seats'] as List? ?? []);
        hand = [
          for (final c in msg['hand'] as List? ?? []) parseCard(c as String),
        ];
        final m = msg['m13'] as Map;
        trick = [
          for (final c in m['last'] as List? ?? [])
            TrickCard(m['last_seat'] as int? ?? 0, parseCard(c as String)),
        ];
        phase = _phases[msg['phase']] ?? phase;
        turn = msg['turn'] as int? ?? turn;
        _canPassNow = msg['can_pass'] == true;
        if (!predicted && (msg['cards'] as List? ?? []).isNotEmpty) {
          tableMotion = TableMotionEvent(TableMotionKind.play, null, null, [
            for (final c in msg['cards'] as List)
              TrickCard(msg['action_seat'] as int, parseCard(c as String)),
          ]);
        }
      case 'game_start' || 'snapshot':
        _resetMotion();
        completedTrick = null;
        completedTrickWinner = null;
        suspended = false;
        humanSeat = msg['you'] as int? ?? humanSeat;
        numPlayers = msg['size'] as int? ?? numPlayers;
        roomCode = msg['code'] as String?;
        stake = msg['stake'] as int? ?? 0;
        locked = msg['locked'] as bool? ?? false;
        if (msg['config'] is Map) {
          config = RuleConfig.fromJson({
            'rulesVersion': 1,
            ...(msg['config'] as Map).cast<String, dynamic>(),
          });
        }
        seats = _parseSeats(msg['seats'] as List? ?? []);
        started = msg['started'] as bool? ?? true;
        gameOver = false;
        drawn = false;
        if (msg['push'] == 'game_start') winners = null;
        if (msg['push'] == 'snapshot') {
          roundNo = msg['round'] as int? ?? roundNo;
          phase = started ? _phases[msg['phase']] ?? phase : Phase.deciding;
          gameOver = started && phase == Phase.gameEnd;
          drawn = msg['draw'] == true;
          if (msg['winners'] is List) {
            winners = (msg['winners'] as List).cast<int>();
          }
          _canPassNow = msg['can_pass'] as bool? ?? false;
          turn = msg['turn'] as int? ?? turn;
          dealer = msg['dealer'] as int? ?? dealer;
          if (msg['trump'] is String) {
            trumpCard = parseCard(msg['trump'] as String);
            trumpSuit = msg['trump_suit'] as int? ?? suitOf(trumpCard);
            trumpTaken = msg['trump_taken'] == true;
          }
          if (isThousand) trumpSuit = msg['trump_suit'] as int? ?? -1;
          stockCount = msg['stock'] as int? ?? 0;
          trick = [
            for (final t in (msg['trick'] as List? ?? []))
              TrickCard(t['seat'] as int, parseCard(t['card'] as String)),
          ];
          if (isMongol13 && msg['m13'] is Map) {
            final m = msg['m13'] as Map;
            trick = [
              for (final c in m['last'] as List? ?? [])
                TrickCard(m['last_seat'] as int? ?? 0, parseCard(c as String)),
            ];
          }
          hand = [
            for (final c in (msg['hand'] as List? ?? []))
              parseCard(c as String),
          ];
          final dl = msg['deadline'] as int?;
          turnDeadline = dl == null
              ? null
              : DateTime.now().add(Duration(milliseconds: dl * 10));
        }
      case 'round_start':
        _resetMotion();
        tableMotion = TableMotionEvent(TableMotionKind.deal);
        phase = Phase.deciding;
        started = true;
        roundNo = msg['round'] as int;
        dealer = msg['dealer'] as int;
        if (msg['trump'] is String) {
          trumpCard = parseCard(msg['trump'] as String);
        }
        trumpSuit =
            msg['trump_suit'] as int? ?? (isThousand ? -1 : suitOf(trumpCard));
        trumpTaken = false;
        stockCount = msg['stock'] as int;
        // Spectators receive public round updates without private cards.
        hand = [
          for (final c in msg['hand'] as List? ?? []) parseCard(c as String),
        ];
        trick = [];
        completedTrick = null;
        completedTrickWinner = null;
        final scoreList = (msg['scores'] as List).cast<int>();
        for (var s = 0; s < scoreList.length; s++) {
          _updateSeat(
            s,
            score: scoreList[s],
            tricks: 0,
            wonCards: const [],
            decision: Decision.none,
          );
        }
      case 'turn':
        _awaitingPlayTurn = false;
        turn = msg['seat'] as int;
        phase = _phases[msg['phase']] ?? phase;
        _canPassNow = msg['can_pass'] as bool? ?? true;
        final dl = msg['deadline'] as int? ?? 0;
        turnDeadline = DateTime.now().add(Duration(milliseconds: dl * 10));
      case 'decided':
        _updateSeat(
          msg['seat'] as int,
          decision: msg['play'] == true ? Decision.play : Decision.pass,
        );
      case 'exchanged':
        final count = msg['count'] as int? ?? 0;
        stockCount = (stockCount - count).clamp(0, 32);
      case 'exchange_result':
        hand = [for (final c in msg['hand'] as List) parseCard(c as String)];
      case 'trump_taken':
        trumpCard = parseCard(msg['trump'] as String);
        trumpTaken = true;
      case 'played':
        final seat = msg['seat'] as int;
        final card = parseCard(msg['card'] as String);
        final predicted =
            _pendingPlay?.seat == seat && _pendingPlay?.card == card;
        if (seat == humanSeat) {
          if (_pendingPlay != null && !predicted) _resetMotion();
          _pendingPlay = null;
          _awaitingPlayTurn = true;
        }
        if (!predicted) {
          tableMotion = TableMotionEvent(
            TableMotionKind.play,
            TrickCard(seat, card),
          );
        }
        trick = [...trick, TrickCard(seat, card)];
        if (seat == humanSeat) hand = [...hand]..remove(card);
      case 'trick_end':
        final winner = msg['winner'] as int;
        final winningCard = msg['winning_card'] is String
            ? parseCard(msg['winning_card'] as String)
            : trick.where((t) => t.seat == winner).firstOrNull?.card;
        completedTrick = trick;
        completedTrickWinner = winner;
        trick = [];
        _updateSeat(
          winner,
          tricks: seats[winner].tricks + 1,
          wonCards: [
            ...seats[winner].wonCards,
            if (winningCard != null &&
                !seats[winner].wonCards.contains(winningCard))
              winningCard,
          ],
        );
        // After a short look at the full trick, the cards fly to the winner.
        Timer(const Duration(milliseconds: 380), () {
          if (_disposed || completedTrickWinner != winner) return;
          tableMotion = TableMotionEvent(TableMotionKind.collect, null, winner);
          notifyListeners();
        });
        Timer(trickPause, () {
          if (_disposed) return;
          completedTrick = null;
          completedTrickWinner = null;
          notifyListeners();
        });
      case 'round_end':
        phase = Phase.roundEnd;
        for (final r in (msg['results'] as List).cast<Map<String, dynamic>>()) {
          _updateSeat(
            r['seat'] as int,
            score: r['score'] as int,
            tricks: r['tricks'] as int,
          );
        }
      case 'game_end':
        drawn = msg['draw'] == true;
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
        _updateSeat(
          seat,
          online: msg['online'] as bool?,
          auto: msg['auto'] as bool?,
        );
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
        locked = msg['locked'] as bool? ?? locked;
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
