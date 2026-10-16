import 'dart:async';

import 'package:card/audio/audio_controller.dart';
import 'package:card/audio/sounds.dart';
import 'package:card/game/game_controller.dart';
import 'package:card/game/remote_game.dart';
import 'package:card/net/net_client.dart';
import 'package:card/net/session.dart';
import 'package:card/play_session/card_widget.dart';
import 'package:card/play_session/play_session_screen.dart';
import 'package:card/play_session/table_motion.dart';
import 'package:card/play_session/turn_countdown_avatar.dart';
import 'package:card/rtc/table_call_controller.dart';
import 'package:card/rtc/table_call_widgets.dart';
import 'package:card/rules/card.dart' as cards;
import 'package:card/rules/rules.dart';
import 'package:card/settings/persistence/memory_settings_persistence.dart';
import 'package:card/settings/settings.dart';
import 'package:card/style/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Client extends NetClient {
  final events = StreamController<Map<String, dynamic>>.broadcast();
  final requests = <Completer<Map<String, dynamic>>>[];
  final commands = <String>[];
  final arguments = <Map<String, dynamic>?>[];
  @override
  Stream<Map<String, dynamic>> get pushes => events.stream;
  @override
  Future<Map<String, dynamic>> call(String cmd, [Map<String, dynamic>? args]) {
    commands.add(cmd);
    arguments.add(args);
    final request = Completer<Map<String, dynamic>>();
    requests.add(request);
    return request.future;
  }
}

class _Session extends Session {
  final _client = _Client();
  @override
  _Client get client => _client;
}

class _SilentAudio implements AudioController {
  @override
  void playSfx(SfxType type) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _push(_Session session, Map<String, dynamic> message) async {
  session.client.events.add(message);
  await Future<void>.delayed(Duration.zero);
}

RemoteGameController _gameFor(_Session session) => RemoteGameController(session)
  ..started = true
  ..humanSeat = 0
  ..numPlayers = 2
  ..roundNo = 1
  ..turn = 0
  ..phase = Phase.playing
  ..hand = [7, 8, 9, 10, 11]
  ..seats = List.generate(
    2,
    (i) => SeatView(
      name: 'Player $i',
      score: 20,
      tricks: 0,
      decision: Decision.play,
      bot: i != 0,
    ),
  );

final flights = find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('flying-'),
);

Future<void> _mount(
  WidgetTester tester,
  _Session session,
  RemoteGameController game, {
  bool reduced = false,
  Size size = const Size(800, 900),
  double scale = 1,
  TableCallController? call,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider(
          create: (_) =>
              SettingsController(store: MemoryOnlySettingsPersistence()),
        ),
        Provider(create: (_) => Palette()),
        Provider<AudioController>(create: (_) => _SilentAudio()),
        ChangeNotifierProvider<Session>.value(value: session),
        ChangeNotifierProvider<GameController>.value(value: game),
        if (call != null)
          ChangeNotifierProvider<TableCallController>.value(value: call),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: const TableView(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'Muushig waits on the table, hides bot start/cancel, confirms host dissolution',
    (tester) async {
      final session = _Session();
      final game = _gameFor(session)
        ..started = false
        ..roomCode = '123456'
        ..numPlayers = 5;
      await _mount(tester, session, game, size: const Size(390, 844));
      expect(find.byKey(const ValueKey('table-empty-seat-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('table-hand')), findsNothing);
      expect(find.byKey(const ValueKey('table-stock')), findsNothing);
      expect(find.byKey(const ValueKey('table-actions')), findsNothing);
      expect(find.text('Invite friends'), findsOneWidget);
      expect(find.text('Start with bots'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Dissolve this room?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(session.client.commands, isEmpty);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dissolve room'));
      await tester.pumpAndSettle();
      expect(session.client.commands, ['dissolve_room']);
      session.client.requests.single.completeError(
        NetException('already_started'),
      );
      await tester.pumpAndSettle();
      expect(game.roomCode, '123456');
      await tester.pumpWidget(const SizedBox());
      game.dispose();
      await session.client.events.close();
    },
  );

  test(
    'Dissolution clears the matching table and ignores another room notification',
    () async {
      final session = _Session();
      final game = _gameFor(session)..roomCode = '123456';
      await _push(session, {'push': 'room_dissolved', 'code': 'other'});
      expect(game.roomCode, '123456');
      await _push(session, {'push': 'room_dissolved', 'code': '123456'});
      expect(game.roomCode, isNull);
      expect(game.seats, isEmpty);
      expect(game.roomDissolved, isTrue);
      await _push(session, {
        'push': 'room_update',
        'code': '654321',
        'size': 2,
        'seats': [
          {'name': 'Host'},
        ],
      });
      expect(game.roomCode, '654321');
      expect(game.roomDissolved, isFalse);
      game.dispose();
      await session.client.events.close();
    },
  );
  test(
    'Thousand optimistic play returns on rejection and state restores variable trump',
    () async {
      final session = _Session();
      final game = _gameFor(session)
        ..gameType = 'thousand'
        ..trumpSuit = -1;
      addTearDown(game.dispose);
      addTearDown(session.client.events.close);
      final request = game.thousandAction('play', value: '9C');
      expect(game.displayHand, isNot(contains(9)));
      expect(game.displayTrick.last.card, 9);
      expect(game.playPending, isTrue);
      session.client.requests.single.completeError(
        NetException('thousand_follow_suit'),
      );
      await request;
      expect(game.displayHand, contains(9));
      expect(game.playPending, isFalse);
      await _push(session, {
        'push': 'snapshot',
        'game_type': 'thousand',
        'started': true,
        'size': 3,
        'you': 0,
        'phase': 'playing',
        'turn': 0,
        'trump_suit': -1,
        'hand': ['KH', 'QH'],
        'seats': [
          {'name': 'A', 'score': 880, 'tricks': 1},
          {'name': 'B'},
          {'name': 'C'},
        ],
        'thousand': {
          'stage': 'play',
          'contract': 140,
          'bidder': 0,
          'details': [
            {'points': 30, 'bonus': 0, 'barrel': true, 'attempts': 1},
          ],
        },
      });
      expect(game.trumpSuit, -1);
      expect(game.thousandContract, 140);
      expect(game.canAnnounceThousand(cards.parseCard('KH')), isTrue);
      await _push(session, {
        'push': 'thousand_state',
        'you': 0,
        'size': 3,
        'seats': [
          {'name': 'A', 'tricks': 1},
          {'name': 'B'},
          {'name': 'C'},
        ],
        'phase': 'playing',
        'turn': 1,
        'trump': 'KH',
        'trump_suit': 2,
        'hand': ['QH'],
        'trick': [
          {'seat': 0, 'card': 'KH'},
        ],
        'thousand': {'stage': 'play', 'contract': 140, 'bidder': 0},
      });
      expect(game.trumpSuit, 2);
      expect(game.hand, [cards.parseCard('QH')]);
      expect(game.trick.single.card, cards.parseCard('KH'));
    },
  );
  for (final stage in ['bid', 'give', 'contract', 'play']) {
    testWidgets('Thousand $stage controls fit phone with large text', (
      tester,
    ) async {
      final session = _Session();
      final game = _gameFor(session)
        ..gameType = 'thousand'
        ..numPlayers = 3
        ..trumpSuit = -1
        ..phase = (stage == 'bid'
            ? Phase.deciding
            : stage == 'play'
            ? Phase.playing
            : Phase.exchanging)
        ..hand = [
          '9C',
          'JC',
          'QC',
          'KC',
          'TC',
          'AC',
          'KH',
          'QH',
        ].map(cards.parseCard).toList()
        ..thousand = {
          'stage': stage,
          'bid': 100,
          'contract': 100,
          'bidder': 0,
          'kitty': ['9H', 'AH', 'AS'],
          'details': [
            {'points': 30, 'bonus': 0, 'barrel': true, 'attempts': 1},
          ],
        }
        ..seats = List.generate(
          3,
          (i) => SeatView(
            name: 'Player $i',
            score: 0,
            tricks: 1,
            decision: Decision.play,
            handCount: 8,
          ),
        );
      addTearDown(game.dispose);
      addTearDown(session.client.events.close);
      await _mount(
        tester,
        session,
        game,
        size: const Size(360, 800),
        scale: 1.5,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Thousand · ${game.roomCode ?? ''}'), findsNothing);
      if (stage == 'give') expect(find.text('Give cards'), findsOneWidget);
      if (stage == 'play') expect(find.text('Declare K+Q'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  test(
    'Durak rematch blocks duplicate requests and recovers from failure',
    () async {
      final session = _Session();
      final game = _gameFor(session)
        ..gameType = 'durak'
        ..gameOver = true;
      addTearDown(game.dispose);
      addTearDown(session.client.events.close);
      final request = game.restartDurak();
      await game.restartDurak();
      expect(session.client.requests.length, 1);
      expect(game.restarting, isTrue);
      session.client.requests.last.completeError(NetException('timeout'));
      await request;
      expect(game.restarting, isFalse);
      expect(game.playError, 'timeout');
    },
  );
  testWidgets(
    'Durak renders six video seats and paired attack/cover cards in a narrow viewport',
    (tester) async {
      final session = _Session();
      final game = _gameFor(session)
        ..gameType = 'durak'
        ..numPlayers = 6
        ..hand = [6, 7, 8, 9, 10, 11]
        ..durak = {
          'stage': 'defend',
          'attacker': 1,
          'defender': 0,
          'pairs': [
            {'attack': '6D', 'attack_seat': 1},
          ],
          'limit': 5,
          'transfer': true,
        }
        ..seats = List.generate(
          6,
          (i) => SeatView(
            name: 'Player $i',
            score: 0,
            tricks: 0,
            handCount: 6,
            decision: Decision.play,
          ),
        );
      addTearDown(game.dispose);
      addTearDown(session.client.events.close);
      await _mount(tester, session, game, size: const Size(355, 486));
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 6; i++) {
        expect(find.byKey(ValueKey('table-seat-$i')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('durak-pair-0')), findsOneWidget);
      final req = game.durakAction('defend', cards: [7], target: 0);
      expect(game.displayHand, isNot(contains(7)));
      expect(game.displayDurakPairs.first.cover, 7);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(flights, findsOneWidget);
      session.client.requests.last.completeError(
        NetException('durak_cannot_beat'),
      );
      await req;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(game.hand, contains(7));
      expect(game.displayDurakPairs.first.cover, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'Durak reconnect restores pairs and draw result; a state push commits optimistic attack once',
    () async {
      final session = _Session();
      final game = _gameFor(session)
        ..gameType = 'durak'
        ..hand = [7, 8, 9];
      addTearDown(game.dispose);
      addTearDown(session.client.events.close);
      final req = game.durakAction('attack', cards: [7]);
      expect(game.displayDurakPairs.length, 1);
      await _push(session, {
        'push': 'durak_state',
        'game_type': 'durak',
        'you': 0,
        'size': 2,
        'phase': 'playing',
        'turn': 1,
        'seats': [],
        'hand': ['8C', '9C'],
        'stock': 12,
        'action_seat': 0,
        'cards': ['7C'],
        'durak': {
          'stage': 'defend',
          'pairs': [
            {'attack': '7C', 'attack_seat': 0},
          ],
        },
      });
      session.client.requests.last.complete({});
      await req;
      expect(game.displayDurakPairs.length, 1);
      expect(game.hand, [8, 9]);
      expect(game.playPending, isFalse);
      await _push(session, {
        'push': 'snapshot',
        'game_type': 'durak',
        'you': 0,
        'size': 2,
        'started': true,
        'phase': 'game_end',
        'draw': true,
        'winners': [],
        'durak': {
          'stage': 'add',
          'pairs': [
            {'attack': '7C', 'attack_seat': 0, 'cover': '8C', 'cover_seat': 1},
          ],
        },
      });
      expect(game.drawn, isTrue);
      expect(game.gameOver, isTrue);
      expect(game.displayDurakPairs.first.cover, 8);
    },
  );
  testWidgets(
    'Mongol 13 seated guests wait for host without exposing table actions',
    (tester) async {
      final session = _Session();
      final game = _gameFor(session)
        ..gameType = 'mongol13'
        ..started = false
        ..humanSeat = 1
        ..roomCode = '131313';
      addTearDown(game.dispose);
      addTearDown(session.client.events.close);
      await _mount(tester, session, game, size: const Size(355, 486));
      expect(find.byKey(const ValueKey('table-actions')), findsNothing);
      expect(find.text('Start game'), findsNothing);
      expect(find.text('Waiting for friends…'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Mongol 13 has 13 selectable cards, combo hint and batch rollback',
    (tester) async {
      final session = _Session();
      final game = _gameFor(session)
        ..gameType = 'mongol13'
        ..hand = [
          '3D',
          '4C',
          '5H',
          '6S',
          '7D',
          '8S',
          '9D',
          'TD',
          'JS',
          'QS',
          'KH',
          'AD',
          '3C',
        ].map(cards.parseCard).toList();
      addTearDown(game.dispose);
      addTearDown(session.client.events.close);
      await _mount(tester, session, game, size: const Size(390, 844));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('table-stock')), findsNothing);
      expect(find.byType(CardView), findsNWidgets(13));
      await tester.ensureVisible(find.text('Hint'));
      await tester.tap(find.text('Hint'));
      await tester.pump();
      expect(
        tester
            .widgetList<CardView>(find.byType(CardView))
            .where((c) => c.selected)
            .length,
        5,
      );
      await tester.tap(find.text('Play'));
      expect(game.displayHand.length, 8);
      expect(game.displayTrick.length, 5);
      expect(game.playPending, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(flights, findsNWidgets(5));
      session.client.requests.last.completeError(NetException('m13_too_small'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(game.displayHand.length, 13);
      expect(game.playPending, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'Mongol 13 ack commits once and reconnect restores a combination',
    () async {
      final session = _Session();
      final game = _gameFor(session)
        ..gameType = 'mongol13'
        ..hand = [3, 19, 4];
      addTearDown(game.dispose);
      addTearDown(session.client.events.close);
      final request = game.playCombo([3, 19]);
      expect(game.displayHand, [4]);
      await _push(session, {
        'push': 'm13_state',
        'game_type': 'mongol13',
        'you': 0,
        'size': 2,
        'phase': 'playing',
        'turn': 1,
        'seats': [],
        'hand': ['4C'],
        'action_seat': 0,
        'cards': ['3C', '3D'],
        'm13': {
          'last': ['3C', '3D'],
          'last_seat': 0,
        },
      });
      session.client.requests.last.complete({});
      await request;
      expect(game.hand, [4]);
      expect(game.displayTrick.length, 2);
      expect(game.playPending, isFalse);
      await _push(session, {
        'push': 'snapshot',
        'game_type': 'mongol13',
        'you': 0,
        'size': 2,
        'started': true,
        'phase': 'playing',
        'turn': 0,
        'hand': ['4C'],
        'm13': {
          'last': ['3C', '3D'],
          'last_seat': 1,
        },
        'can_pass': true,
      });
      expect(game.displayTrick.length, 2);
      expect(game.passAllowed, isTrue);
      await _push(session, {
        'push': 'm13_state',
        'game_type': 'mongol13',
        'you': -1,
        'size': 2,
        'phase': 'playing',
        'turn': 0,
        'm13': {'last': []},
      });
      expect(game.spectating, isTrue);
      expect(game.hand, isEmpty);
    },
  );
  test(
    'new rules force trump ace and preserve pass restriction on reconnect',
    () async {
      final session = _Session();
      final game = _gameFor(session);
      addTearDown(game.dispose);
      addTearDown(session.client.events.close);
      await _push(session, {
        'push': 'snapshot',
        'you': 0,
        'size': 2,
        'started': true,
        'phase': 'playing',
        'turn': 0,
        'trump': '7C',
        'hand': ['AC', 'KC', 'QC', 'JC', 'TC'],
        'config': {'rulesVersion': 2},
        'can_pass': false,
      });
      expect(game.legalCards(), [14]);
      expect(game.passAllowed, isFalse);
      await _push(session, {
        'push': 'turn',
        'seat': 0,
        'phase': 'deciding',
        'can_pass': false,
      });
      expect(game.passAllowed, isFalse);
    },
  );
  late _Session session;
  late RemoteGameController game;
  setUp(() {
    session = _Session();
    game = _gameFor(session);
  });
  tearDown(() async {
    game.dispose();
    await session.client.events.close();
  });

  testWidgets(
    'all undecided players choose at once and accepted choices stop their CD',
    (tester) async {
      game.config = const RuleConfig();
      game.phase = Phase.deciding;
      game.turn = 1;
      game.turnDuration = const Duration(seconds: 15);
      game.turnDeadline = DateTime.now().add(const Duration(seconds: 15));
      game.seats = List.generate(
        2,
        (i) => SeatView(
          name: 'Player $i',
          score: 15,
          tricks: 0,
          decision: Decision.none,
        ),
      );
      await _mount(tester, session, game);
      expect(game.humanTurn, isTrue);
      expect(
        tester
            .widgetList<TurnCountdownAvatar>(find.byType(TurnCountdownAvatar))
            .where((a) => a.active),
        hasLength(2),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Play'));
      expect(session.client.commands, ['decide']);
      session.client.events.add({'push': 'decided', 'seat': 0, 'play': true});
      await tester.pump();
      expect(game.humanTurn, isFalse);
      expect(find.textContaining('Waiting for other players'), findsOneWidget);
      expect(
        tester
            .widgetList<TurnCountdownAvatar>(find.byType(TurnCountdownAvatar))
            .where((a) => a.active),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final keep in [true, false]) {
    testWidgets(
      'exchange shows both Keep and Exchange; keep=$keep respects selected cards',
      (tester) async {
        game.phase = Phase.exchanging;
        game.stockCount = 6;
        await _mount(
          tester,
          session,
          game,
          size: const Size(320, 568),
          scale: 1.5,
        );
        final keepButton = find.widgetWithText(FilledButton, 'Keep all');
        final exchangeButton = find.widgetWithText(FilledButton, 'Exchange');
        expect(keepButton, findsOneWidget);
        expect(tester.widget<FilledButton>(exchangeButton).onPressed, isNull);
        final hand = find.byKey(const ValueKey('hand-card-8'));
        await tester.ensureVisible(hand);
        await tester.tap(hand);
        await tester.pump();
        expect(keepButton, findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Exchange 1'), findsOneWidget);
        final action = keep
            ? keepButton
            : find.widgetWithText(FilledButton, 'Exchange 1');
        await tester.ensureVisible(action);
        await tester.tap(action);
        expect(session.client.commands, ['exchange']);
        expect(
          session.client.arguments.single?['cards'],
          keep ? isEmpty : ['8C'],
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test(
    'dealer trade keeps original trump through pushes and reconnect',
    () async {
      await _push(session, {
        'push': 'round_start',
        'round': 11,
        'dealer': 1,
        'trump': '8D',
        'trump_suit': 1,
        'stock': 0,
        'scores': [15, 15],
      });
      await _push(session, {'push': 'trump_taken', 'seat': 1, 'trump': '8C'});
      expect(game.trumpCard, 8);
      expect(game.trumpIndicatorCard, cards.parseCard('8D'));
      expect(game.trumpSuit, 1);
      expect(game.trumpTaken, isTrue);
      await _push(session, {
        'push': 'snapshot',
        'trump': '8C',
        'trump_suit': 1,
        'trump_taken': true,
        'trump_indicator': '8D',
        'phase': 'playing',
        'turn': 0,
        'hand': ['AC', '7D'],
        'trick': [
          {'seat': 1, 'card': '7H'},
        ],
      });
      expect(game.trumpSuit, 1);
      expect(game.trumpTaken, isTrue);
      expect(game.trumpIndicatorCard, cards.parseCard('8D'));
      expect(game.legalCards(), [
        23,
      ]); // Must trump hearts with diamonds, not clubs.
      await _push(session, {
        'push': 'round_start',
        'round': 12,
        'dealer': 0,
        'trump': 'KC',
        'stock': 0,
        'scores': <int>[],
      });
      expect(game.trumpSuit, 0);
      expect(game.trumpTaken, isFalse);
      expect(game.trumpIndicatorCard, cards.parseCard('KC'));
    },
  );

  test(
    'Turn and snapshot keep the 15-second budget separate from remaining time',
    () async {
      await _push(session, {
        'push': 'turn',
        'seat': 0,
        'phase': 'playing',
        'deadline': 1500,
        'turn_duration': 1500,
      });
      expect(game.turnDuration, const Duration(seconds: 15));
      expect(
        game.turnDeadline!.difference(DateTime.now()).inSeconds,
        inInclusiveRange(14, 15),
      );
      await _push(session, {
        'push': 'snapshot',
        'started': true,
        'phase': 'playing',
        'deadline': 700,
        'turn_duration': 1500,
      });
      expect(game.turnDuration, const Duration(seconds: 15));
      expect(
        game.turnDeadline!.difference(DateTime.now()).inSeconds,
        inInclusiveRange(6, 7),
      );
    },
  );

  testWidgets(
    'dealer exchange keeps the original face-up card visible at the stock',
    (tester) async {
      session.client.events.add({
        'push': 'snapshot',
        'trump': '8C',
        'trump_indicator': '8D',
        'trump_suit': 1,
        'trump_taken': true,
        'started': true,
        'phase': 'playing',
        'hand': ['AC', '7D'],
        'seats': [
          {'name': 'A'},
          {'name': 'B'},
        ],
      });
      await _mount(tester, session, game);
      final stock = find.byKey(const ValueKey('table-stock'));
      final indicator = tester.widget<CardView>(
        find.descendant(of: stock, matching: find.byType(CardView)),
      );
      expect(indicator.card, cards.parseCard('8D'));
      expect(indicator.width, 36);
      expect(find.byKey(const ValueKey('fixed-trump-suit')), findsNothing);
      expect(find.text('Trump'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (size, scale) in [
    (const Size(390, 844), 1.0),
    (const Size(355, 486), 1.0),
    (const Size(390, 844), 2.0),
  ]) {
    testWidgets(
      'Muushig 2-2-1 seats rotate around viewer and stay clear at $size x$scale',
      (tester) async {
        tester.view.padding = const FakeViewPadding(bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(bottom: 34);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        game.numPlayers = 5;
        game.humanSeat = 3;
        game.turn = 3;
        game.phase = Phase.deciding;
        game.seats = List.generate(
          5,
          (i) => SeatView(
            name: 'Long player name $i',
            score: 15,
            tricks: 0,
            decision: Decision.none,
          ),
        );
        await _mount(tester, session, game, size: size, scale: scale);
        Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
        final me = rect('table-seat-3');
        final lowerRight = rect('table-seat-4');
        final upperRight = rect('table-seat-0');
        final upperLeft = rect('table-seat-1');
        final lowerLeft = rect('table-seat-2');
        expect(me.center.dx, closeTo(size.width * .5, 1));
        expect(upperRight.top, upperLeft.top);
        expect(lowerRight.top, lowerLeft.top);
        expect(lowerLeft.bottom, lessThan(me.top));
        expect(upperLeft.right, lessThan(upperRight.left));
        expect(lowerLeft.right, lessThan(lowerRight.left));
        expect(upperLeft.bottom, lessThan(lowerLeft.top));
        expect(me.bottom, lessThan(rect('table-hand').top));
        expect(rect('table-stock').overlaps(lowerLeft), isFalse);
        expect(rect('table-stock').overlaps(me), isFalse);
        expect(rect('table-stock').overlaps(rect('table-center')), isFalse);
        expect(rect('table-stock').top, greaterThan(upperLeft.bottom));
        expect(rect('table-stock').bottom, lessThan(lowerLeft.top - 40));
        expect(rect('table-center').overlaps(upperRight), isFalse);
        expect(rect('table-center').bottom, lessThan(lowerLeft.top));
        expect(rect('table-actions').overlaps(me), isFalse);
        expect(rect('table-actions').overlaps(lowerLeft), isFalse);
        expect(rect('table-actions').bottom, lessThan(rect('table-hand').top));
        expect(
          rect('table-actions').overlaps(rect('table-communication-controls')),
          isFalse,
        );
        await tester.ensureVisible(find.byKey(const ValueKey('table-hand')));
        await tester.pump();
        expect(rect('table-hand').bottom, closeTo(size.height - 34 - 12, .1));
        expect(tester.takeException(), isNull);
        for (final avatar in tester.widgetList<CallAvatar>(
          find.byType(CallAvatar),
        )) {
          expect(avatar.portrait, isFalse);
          expect(avatar.size, const Size.square(46));
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Only live video enlarges Muushig avatars and closing restores them x$scale',
      (tester) async {
        game.numPlayers = 5;
        game.roomCode = '123456';
        game.phase = Phase.deciding;
        game.seats = List.generate(
          5,
          (i) => SeatView(
            name: 'Player $i',
            score: 15,
            tricks: 0,
            decision: Decision.none,
            rtcUid: 100 + i,
          ),
        );
        final call = TableCallController(session, game, supported: false);
        await _mount(
          tester,
          session,
          game,
          call: call,
          size: const Size(355, 486),
          scale: scale,
        );
        CallAvatar avatar(int seat) => tester.widget<CallAvatar>(
          find.descendant(
            of: find.byKey(ValueKey('table-seat-$seat')),
            matching: find.byType(CallAvatar),
          ),
        );
        Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
        expect(avatar(1).size, const Size.square(46));
        call.connected = true;
        call.videos.add(101);
        call.notifyListeners();
        await tester.pump();
        expect(avatar(1).portrait, isTrue);
        expect(avatar(1).size.width, greaterThan(46));
        expect(avatar(0).size, const Size.square(46));
        expect(avatar(2).size, const Size.square(46));
        expect(rect('table-center').bottom, lessThan(rect('table-seat-1').top));
        expect(rect('table-seat-0').bottom, lessThan(rect('table-hand').top));
        expect(tester.takeException(), isNull);
        call.videos.addAll([100, 102, 103, 104]);
        call.notifyListeners();
        await tester.pump();
        expect(rect('table-center').bottom, lessThan(rect('table-seat-1').top));
        expect(rect('table-stock').overlaps(rect('table-seat-1')), isFalse);
        expect(rect('table-stock').overlaps(rect('table-seat-4')), isFalse);
        expect(rect('table-stock').overlaps(rect('table-center')), isFalse);
        expect(
          rect('table-stock').bottom,
          lessThan(rect('table-seat-4').top - 40),
        );
        expect(rect('table-seat-1').bottom, lessThan(rect('table-seat-0').top));
        expect(rect('table-seat-0').bottom, lessThan(rect('table-hand').top));
        expect(tester.takeException(), isNull);
        call.videos.clear();
        call.connected = false;
        call.notifyListeners();
        await tester.pump();
        expect(avatar(1).portrait, isFalse);
        expect(avatar(1).size, const Size.square(46));
        final ownAvatar = find.byKey(const ValueKey('seat-call-control-0'));
        await tester.ensureVisible(ownAvatar);
        await tester.tap(ownAvatar);
        await tester.pumpAndSettle();
        expect(find.text('Camera on'), findsOneWidget);
        expect(find.byType(TableCallButton), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        call.dispose();
        await call.leave();
      },
    );
  }

  test(
    'immediate prediction, duplicate guard, ACK then push commits only once',
    () async {
      game.play('7C');
      final motion = game.tableMotion;
      expect(game.displayHand, isNot(contains(7)));
      expect(game.displayTrick.single.card, 7);
      expect(game.hand, contains(7)); // authoritative state is untouched
      expect(game.trick, isEmpty);
      game.play('8C');
      expect(session.client.requests, hasLength(1));
      session.client.requests.single.complete({});
      await Future<void>.delayed(Duration.zero);
      expect(game.playPending, isTrue);
      await _push(session, {'push': 'played', 'seat': 0, 'card': '7C'});
      expect(game.displayTrick, hasLength(1));
      expect(game.hand, isNot(contains(7)));
      expect(game.tableMotion, same(motion));
      await _push(session, {'push': 'turn', 'seat': 1, 'phase': 'playing'});
      expect(game.playPending, isFalse);
    },
  );

  test(
    'rejection restores hand and permits retry without changing rule state',
    () async {
      game.play('7C');
      session.client.requests.single.completeError(
        NetException('illegal_card'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(game.displayHand, [7, 8, 9, 10, 11]);
      expect(game.displayTrick, isEmpty);
      expect(game.playError, 'illegal_card');
      expect(game.tableMotion!.kind, TableMotionKind.returnCard);
      game.play('8C');
      expect(session.client.requests, hasLength(2));
    },
  );

  test(
    'confirmed push wins over late request error, including final trick',
    () async {
      game.play('7C');
      await _push(session, {'push': 'played', 'seat': 0, 'card': '7C'});
      await _push(session, {'push': 'trick_end', 'winner': 0});
      session.client.requests.single.completeError(NetException('timeout'));
      await Future<void>.delayed(Duration.zero);
      expect(game.displayHand, isNot(contains(7)));
      expect(game.displayTrick.single.card, 7);
      expect(game.playError, isNull);
      expect(game.seats[0].wonCards, [7]);
    },
  );

  test('reconnect snapshot invalidates old prediction and rejection', () async {
    game.play('7C');
    await _push(session, {
      'push': 'snapshot',
      'you': 0,
      'size': 2,
      'round': 2,
      'phase': 'playing',
      'hand': ['8C'],
      'trick': [
        {'seat': 0, 'card': '7C'},
      ],
    });
    session.client.requests.single.completeError(NetException('disconnected'));
    await Future<void>.delayed(Duration.zero);
    expect(game.displayHand, [8]);
    expect(game.displayTrick, hasLength(1));
    expect(game.playError, isNull);
    expect(game.tableMotion!.kind, TableMotionKind.reset);
  });

  test(
    'winning card list restores on reconnect and clears for a new round',
    () async {
      await _push(session, {
        'push': 'trick_end',
        'winner': 1,
        'winning_card': 'AC',
      });
      expect(game.seats[1].wonCards, [14]);
      await _push(session, {
        'push': 'snapshot',
        'you': 0,
        'size': 2,
        'started': true,
        'seats': [
          {'name': 'Me', 'won_cards': []},
          {
            'name': 'Bot',
            'tricks': 2,
            'won_cards': ['AC', 'KC'],
          },
        ],
      });
      expect(game.seats[1].wonCards, [14, 13]);
      await _push(session, {
        'push': 'round_start',
        'round': 2,
        'dealer': 0,
        'trump': '7C',
        'stock': 20,
        'scores': [20, 18],
      });
      expect(game.seats.every((s) => s.wonCards.isEmpty), isTrue);
    },
  );

  testWidgets('winning cards sit above the avatar and bot countdown drains', (
    tester,
  ) async {
    game.turn = 1;
    game.turnDeadline = DateTime.now().add(const Duration(seconds: 6));
    game.seats[1] = const SeatView(
      name: 'Bot',
      score: 18,
      tricks: 2,
      decision: Decision.play,
      bot: true,
      wonCards: [14, 13],
    );
    await _mount(tester, session, game);
    final wins = find.byKey(const ValueKey('won-cards-1'));
    expect(
      find.descendant(of: wins, matching: find.byType(CardView)),
      findsNWidgets(2),
    );
    expect(
      tester.getRect(wins).bottom,
      lessThan(tester.getRect(find.byKey(const ValueKey('table-seat-1'))).top),
    );
    final avatar = find.descendant(
      of: find.byKey(const ValueKey('table-seat-1')),
      matching: find.byType(TurnCountdownAvatar),
    );
    expect(tester.getCenter(wins).dx, closeTo(tester.getCenter(avatar).dx, .1));
    await tester.pump(const Duration(seconds: 2));
    final sweep =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('own-turn-progress')),
                )
                .painter!
            as AvatarCooldownPainter;
    expect(sweep.progress, closeTo(2 / 3, .03));
    expect(sweep.color, const Color(0xffd5fff6));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tap selects a card and Play flies it before the network response',
    (tester) async {
      await _mount(tester, session, game);
      final handCard = find.byWidgetPredicate(
        (w) => w is CardView && w.card == 8 && w.onTap != null,
      );
      await tester.tap(handCard);
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.widget<CardView>(handCard).selected, isTrue);
      expect(session.client.commands, isEmpty);
      expect(flights, findsNothing);
      final selectedCard = find.descendant(
        of: handCard,
        matching: find.byType(AnimatedContainer),
      );
      expect(
        tester
            .widget<AnimatedContainer>(selectedCard)
            .transform!
            .getTranslation()
            .y,
        -12,
      );
      final origin = tester.getCenter(handCard);
      await tester.tap(find.widgetWithText(FilledButton, 'Play'));
      await tester.pump();
      await tester.pump();
      expect(flights, findsOneWidget);
      final first = tester.getCenter(flights);
      expect((first - origin).distance, lessThan(4));
      await tester.pump(const Duration(milliseconds: 140));
      final halfway = tester.getCenter(flights);
      expect(halfway.dy, lessThan(origin.dy - 80));
      expect(session.client.requests.single.isCompleted, isFalse);
      await tester.pump(const Duration(milliseconds: 180));
      expect(flights, findsNothing);
      session.client.events.add({'push': 'played', 'seat': 0, 'card': '8C'});
      await tester.pump();
      expect(flights, findsNothing);
      expect(game.displayTrick, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'tap again deselects and choosing another card replaces selection',
    (tester) async {
      await _mount(tester, session, game);
      Finder card(int value) => find.byWidgetPredicate(
        (w) => w is CardView && w.card == value && w.onTap != null,
      );
      await tester.tap(card(8));
      await tester.pump();
      await tester.tap(card(8));
      await tester.pump();
      expect(tester.widget<CardView>(card(8)).selected, isFalse);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Play'))
            .onPressed,
        isNull,
      );
      await tester.tap(card(8));
      await tester.pump();
      await tester.tap(card(9));
      await tester.pump();
      expect(tester.widget<CardView>(card(8)).selected, isFalse);
      expect(tester.widget<CardView>(card(9)).selected, isTrue);
      expect(session.client.commands, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('short drags and cancellation return the card without playing', (
    tester,
  ) async {
    await _mount(tester, session, game);
    final card = find.byKey(const ValueKey('hand-card-8'));
    final origin = tester.getCenter(card);
    await tester.drag(card, const Offset(0, -40));
    await tester.pump();
    expect(session.client.commands, isEmpty);
    await tester.drag(card, const Offset(100, 0));
    await tester.drag(card, const Offset(0, 100));
    await tester.pump();
    expect(session.client.commands, isEmpty);
    final gesture = await tester.startGesture(origin);
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();
    expect(session.client.commands, isEmpty);
    await gesture.cancel();
    await tester.pump();
    expect(session.client.commands, isEmpty);
    expect(game.displayHand, contains(8));
    expect(flights, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('upward drag plays on release and pending blocks a second play', (
    tester,
  ) async {
    await _mount(tester, session, game);
    final card = find.byKey(const ValueKey('hand-card-8'));
    final origin = tester.getCenter(card);
    final gesture = await tester.startGesture(origin);
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();
    expect(session.client.commands, isEmpty);
    await gesture.up();
    await tester.pump();
    await tester.pump();
    expect(session.client.commands, ['play_card']);
    expect(game.displayHand, isNot(contains(8)));
    expect(flights, findsOneWidget);
    expect(tester.getCenter(flights).dy, closeTo(origin.dy - 120, 4));
    await tester.drag(
      find.byKey(const ValueKey('hand-card-9')),
      const Offset(0, -120),
    );
    await tester.pump();
    expect(session.client.commands, hasLength(1));
    session.client.requests.single.completeError(NetException('illegal_card'));
    await tester.pumpAndSettle();
    expect(game.displayHand, contains(8));
    expect(game.playPending, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (type, command) in [
    ('mongol13', 'play_card'),
    ('durak', 'durak_action'),
    ('thousand', 'thousand_action'),
  ]) {
    testWidgets('$type dragging shares the normal play action', (tester) async {
      game.gameType = type;
      game.hand = [8, 24, 9];
      if (game.isThousand) {
        game.hand = [9, 10, 11];
        game.thousand = {'stage': 'play', 'contract': 100, 'bidder': 0};
      }
      await _mount(tester, session, game);
      await tester.ensureVisible(find.byKey(const ValueKey('table-hand')));
      await tester.pump();
      final draggedCard = game.isThousand
          ? 9
          : game.isMongol13
          ? 24
          : 8;
      if (game.isMongol13) {
        await tester.tap(find.byKey(const ValueKey('hand-card-8')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('hand-card-24')));
        await tester.pump();
        expect(session.client.commands, isEmpty);
      }
      await tester.drag(
        find.byKey(ValueKey('hand-card-$draggedCard')),
        const Offset(0, -120),
      );
      await tester.pump();
      expect(session.client.commands, [command]);
      expect(game.displayHand, isNot(contains(draggedCard)));
      if (game.isMongol13) {
        expect(game.displayHand, [9]);
        expect(game.displayTrick, hasLength(2));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('losing the turn during a drag cannot submit a card', (
    tester,
  ) async {
    await _mount(tester, session, game);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('hand-card-8'))),
    );
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();
    game.turn = 1;
    game.notifyListeners();
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(session.client.commands, isEmpty);
    expect(game.displayHand, contains(8));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fast rejection reverses in-flight card and shows a reason', (
    tester,
  ) async {
    await _mount(tester, session, game);
    game.play('8C');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final before = tester.getCenter(flights);
    session.client.requests.single.completeError(NetException('illegal_card'));
    await tester.pump();
    await tester.pump();
    expect(flights, findsOneWidget);
    expect((tester.getCenter(flights) - before).distance, lessThan(8));
    await tester.pumpAndSettle();
    expect(flights, findsNothing);
    expect(game.displayHand, contains(8));
    expect(find.textContaining('Follow the required suit'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('deal staggers cards and finishes with all five hand cards', (
    tester,
  ) async {
    game.phase = Phase.deciding;
    game.tableMotion = TableMotionEvent(TableMotionKind.deal);
    await _mount(tester, session, game);
    final motion = tester.state<CardTableMotionState>(
      find.byType(CardTableMotion),
    );
    expect(motion.dealing, isTrue);
    expect(flights, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(flights.evaluate().length, greaterThan(1));
    await tester.pumpAndSettle();
    expect(motion.dealing, isFalse);
    expect(flights, findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is CardView && w.onTap != null),
      findsNWidgets(5),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion keeps optimistic feedback without flights', (
    tester,
  ) async {
    await _mount(tester, session, game, reduced: true);
    game.play('8C');
    await tester.pump();
    expect(game.displayHand, isNot(contains(8)));
    expect(game.displayTrick.single.card, 8);
    expect(flights, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('same-frame rejection leaves no orphaned flight or hidden card', (
    tester,
  ) async {
    await _mount(tester, session, game);
    game.play('8C');
    session.client.requests.single.completeError(NetException('offline'));
    await tester.pumpAndSettle();
    expect(flights, findsNothing);
    expect(game.displayHand, contains(8));
    expect(
      tester
          .state<CardTableMotionState>(find.byType(CardTableMotion))
          .animating,
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('spectator deal flies only card backs without private hands', (
    tester,
  ) async {
    game.humanSeat = -1;
    game.hand = [];
    game.phase = Phase.deciding;
    game.tableMotion = TableMotionEvent(TableMotionKind.deal);
    await _mount(tester, session, game);
    await tester.pump(const Duration(milliseconds: 200));
    expect(flights.evaluate().length, greaterThan(1));
    expect(
      find.descendant(of: flights, matching: find.byType(CardView)),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(flights, findsNothing);
    expect(game.displayHand, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
