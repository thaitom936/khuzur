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
  @override
  Stream<Map<String, dynamic>> get pushes => events.stream;
  @override
  Future<Map<String, dynamic>> call(String cmd, [Map<String, dynamic>? args]) {
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
      expect(game.trumpSuit, 1);
      expect(game.trumpTaken, isTrue);
      await _push(session, {
        'push': 'snapshot',
        'trump': '8C',
        'trump_suit': 1,
        'trump_taken': true,
        'phase': 'playing',
        'turn': 0,
        'hand': ['AC', '7D'],
        'trick': [
          {'seat': 1, 'card': '7H'},
        ],
      });
      expect(game.trumpSuit, 1);
      expect(game.trumpTaken, isTrue);
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
    },
  );

  testWidgets(
    'traded-away indicator shows fixed trump suit instead of discard',
    (tester) async {
      game.trumpCard = 8;
      game.trumpSuit = 1;
      game.trumpTaken = true;
      await _mount(tester, session, game);
      final stock = find.byKey(const ValueKey('table-stock'));
      final marker = find.byKey(const ValueKey('fixed-trump-suit'));
      expect(
        find.descendant(of: stock, matching: find.byType(CardView)),
        findsNothing,
      );
      expect(
        find.descendant(of: marker, matching: find.text('♦')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: marker, matching: find.text('Trump')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final (size, scale) in [
    (const Size(390, 844), 1.0),
    (const Size(355, 486), 1.0),
    (const Size(390, 844), 2.0),
  ]) {
    testWidgets(
      'five seats rotate around viewer and stay clear at $size x$scale',
      (tester) async {
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
        final upperRight = rect('table-seat-0');
        final upperLeft = rect('table-seat-1');
        final lowerLeft = rect('table-seat-2');
        final lowerRight = rect('table-seat-4');
        expect(me.center.dx, closeTo(size.width / 2, 1));
        expect(upperRight.top, upperLeft.top);
        expect(lowerRight.top, lowerLeft.top);
        expect(upperLeft.bottom, lessThan(lowerLeft.top));
        expect(lowerLeft.bottom, lessThan(me.top));
        expect(me.bottom, lessThan(rect('table-hand').top));
        expect(rect('table-stock').overlaps(lowerLeft), isFalse);
        expect(rect('table-actions').overlaps(me), isFalse);
        expect(rect('table-actions').overlaps(lowerRight), isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
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
    final ring = tester.widget<CircularProgressIndicator>(
      find.byKey(const ValueKey('own-turn-progress')),
    );
    expect(ring.value, closeTo(2 / 3, .03));
    expect(ring.color, const Color(0xffd5fff6));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one tap flies from hand towards centre before network response',
    (tester) async {
      await _mount(tester, session, game);
      final handCard = find.byWidgetPredicate(
        (w) => w is CardView && w.card == 8 && w.onTap != null,
      );
      final origin = tester.getCenter(handCard);
      await tester.tap(handCard);
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
