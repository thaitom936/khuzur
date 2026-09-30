import 'dart:async';
import 'package:card/game/game_controller.dart';
import 'package:card/game/remote_game.dart';
import 'package:card/net/net_client.dart';
import 'package:card/net/session.dart';
import 'package:card/online/lobby_widgets.dart';
import 'package:card/online/online_screen.dart';
import 'package:card/play_session/play_session_screen.dart';
import 'package:card/play_session/spectator_controls.dart';
import 'package:card/rules/rules.dart';
import 'package:card/settings/persistence/memory_settings_persistence.dart';
import 'package:card/settings/settings.dart';
import 'package:card/style/palette.dart';
import 'package:card/style/player_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> room(
  String code, {
  bool started = false,
  int bots = 0,
  int seated = 2,
  int stake = 0,
}) => {
  'code': code,
  'size': 5,
  'seated': seated,
  'bots': bots,
  'started': started,
  'stake': stake,
  'round': 2,
  'mode': bots > 0 ? 'bot' : 'friend',
  'names': ['A very long player name that must fit', 'Bataa'],
};

class FakeClient extends NetClient {
  bool fail = false;
  final events = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get pushes => events.stream;
  Completer<Map<String, dynamic>>? seatRequest;
  final commands = <String>[];
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> call(
    String cmd, [
    Map<String, dynamic>? args,
  ]) async {
    commands.add(cmd);
    if (cmd == 'join_room' && seatRequest != null) return seatRequest!.future;
    if (cmd == 'room_list') {
      if (pending != null) return pending!.future;
      if (fail) throw NetException('timeout');
      return {
        'rooms': [
          room('100001'),
          room('100002', started: true, bots: 5, seated: 5),
        ],
      };
    }
    return {'coins': 1000};
  }
}

class FakeSession extends Session {
  final FakeClient _fakeClient = FakeClient();
  @override
  FakeClient get client => _fakeClient;
  bool offline = false;
  @override
  Future<void> ensureOnline() async {
    if (offline) throw NetException('login_failed');
    user = UserInfo(
      uid: 1,
      name: 'Player',
      games: 0,
      wins: 0,
      coins: 1000,
      rating: 1000,
      level: 1,
    );
    client.state.value = ConnState.online;
    notifyListeners();
  }

  @override
  Future<void> refreshCoins() async {}
}

Future<void> mountLobby(
  WidgetTester tester,
  FakeSession session, {
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider(
          create: (_) =>
              SettingsController(store: MemoryOnlySettingsPersistence()),
        ),
        ChangeNotifierProvider<Session>.value(value: session),
        ChangeNotifierProvider(create: (_) => RemoteGameController(session)),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: lobbyGreen),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const OnlineScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  test('spectator handles a new round without receiving a hand', () async {
    final session = FakeSession();
    final game = RemoteGameController(session);
    session.client.events.add({
      'push': 'snapshot',
      'you': -1,
      'started': false,
      'code': '123456',
      'size': 3,
      'seats': [
        {'name': 'Host'},
      ],
    });
    await Future<void>.delayed(Duration.zero);
    expect(game.spectating, isTrue);
    expect(game.canTakeSeat, isTrue);
    session.client.events.add({
      'push': 'round_start',
      'round': 1,
      'dealer': 0,
      'trump': '7C',
      'stock': 10,
      'scores': [20],
    });
    await Future<void>.delayed(Duration.zero);
    expect(game.started, isTrue);
    expect(game.hand, isEmpty);
    expect(game.spectating, isTrue);
    session.client.events.add({
      'push': 'snapshot',
      'you': 1,
      'started': true,
      'code': '123456',
      'size': 3,
      'seats': [
        {'name': 'Host'},
        {'name': 'Me'},
      ],
      'hand': ['7C', '8C'],
    });
    await Future<void>.delayed(Duration.zero);
    expect(game.spectating, isFalse);
    expect(game.hand, hasLength(2));
    game.dispose();
    await session.client.events.close();
  });

  testWidgets(
    'sitting is explicit, blocks duplicate clicks, and keeps watching on failure',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final session = FakeSession();
      await session.ensureOnline();
      final game = RemoteGameController(session)
        ..humanSeat = -1
        ..started = false
        ..numPlayers = 3
        ..roomCode = '123456'
        ..seats = [
          const SeatView(
            name: 'Bot',
            score: 20,
            tricks: 0,
            decision: Decision.none,
            bot: true,
          ),
        ];
      session.client.seatRequest = Completer();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider(
              create: (_) =>
                  SettingsController(store: MemoryOnlySettingsPersistence()),
            ),
            ChangeNotifierProvider<Session>.value(value: session),
          ],
          child: MaterialApp(
            home: Scaffold(body: SpectatorControls(game: game)),
          ),
        ),
      );
      await tester.pump();
      expect(session.client.commands, isEmpty);
      await tester.tap(find.text('Sit down'));
      await tester.pump();
      await tester.tap(find.text('Sit down'));
      expect(
        session.client.commands.where((c) => c == 'join_room'),
        hasLength(1),
      );
      session.client.seatRequest!.completeError(NetException('room_full'));
      await tester.pumpAndSettle();
      expect(find.text('Room is full'), findsOneWidget);
      expect(game.spectating, isTrue);
      await tester.pumpWidget(const SizedBox());
      game.dispose();
      await session.client.events.close();
    },
  );

  testWidgets('seated table fits a short window without covering the hand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(355, 486);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final session = FakeSession();
    await session.ensureOnline();
    final game = RemoteGameController(session)
      ..humanSeat = 0
      ..started = true
      ..numPlayers = 5
      ..roomCode = '123456'
      ..hand = [7, 8, 9, 10, 11]
      ..seats = List.generate(
        5,
        (i) => SeatView(
          name: 'Player $i',
          score: 20,
          tricks: 0,
          decision: Decision.none,
          bot: i != 0,
        ),
      );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider(
            create: (_) =>
                SettingsController(store: MemoryOnlySettingsPersistence()),
          ),
          Provider(create: (_) => Palette()),
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<GameController>.value(value: game),
        ],
        child: const MaterialApp(home: TableView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    game.dispose();
    await session.client.events.close();
  });

  test('availability allows seats only before the game starts', () {
    expect(
      LobbyRoom(room('1', started: true, bots: 5, stake: 100)).canSit,
      isFalse,
    );
    expect(LobbyRoom(room('2', seated: 5)).canSit, isFalse);
    expect(LobbyRoom(room('3', started: true, bots: 5)).canSit, isFalse);
    expect(LobbyRoom(room('4', seated: 2)).canSit, isTrue);
  });
  testWidgets('rooms visible on first screen and filters work', (tester) async {
    await mountLobby(tester, FakeSession());
    expect(
      find.byKey(const ValueKey('room-100001')).hitTestable(),
      findsOneWidget,
    );
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Waiting'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Waiting'));
    await tester.pump();
    expect(find.byKey(const ValueKey('room-100001')), findsOneWidget);
    expect(find.byKey(const ValueKey('room-100002')), findsNothing);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Playing'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Playing'));
    await tester.pump();
    expect(find.byKey(const ValueKey('room-100001')), findsNothing);
    expect(find.byKey(const ValueKey('room-100002')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('tapping a room enters as a spectator with no Join button', (
    tester,
  ) async {
    final session = FakeSession();
    await mountLobby(tester, session);
    expect(find.text('#100001'), findsNothing);
    expect(find.text('Public table'), findsNothing);
    expect(find.text('Free'), findsNothing);
    expect(find.text('Bataa'), findsWidgets);
    expect(find.byType(PlayerAvatar), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Join'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('room-100001')));
    await tester.pumpAndSettle();
    expect(session.client.commands, contains('watch'));
    expect(session.client.commands, isNot(contains('join_room')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed refresh retains rooms; retry recovers', (tester) async {
    final session = FakeSession();
    await mountLobby(tester, session);
    session.client.fail = true;
    await tester.tap(find.byTooltip('Refresh tables'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('room-100001')), findsOneWidget);
    expect(
      find.text('Could not refresh tables. Please retry.'),
      findsOneWidget,
    );
    session.client.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Could not refresh tables. Please retry.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('loading, empty and offline states are distinct', (tester) async {
    final session = FakeSession();
    session.client.pending = Completer();
    await mountLobby(tester, session);
    expect(find.text('Finding tables…'), findsOneWidget);
    expect(find.text('No open tables'), findsNothing);
    session.client.pending!.complete({'rooms': []});
    await tester.pumpAndSettle();
    expect(find.text('No open tables'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await mountLobby(tester, FakeSession()..offline = true);
    expect(find.text('Could not connect. Please try again.'), findsOneWidget);
    expect(find.text('Single player'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Create room'),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
  for (final size in [
    const Size(355, 486),
    const Size(360, 640),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    testWidgets('layout fits $size', (tester) async {
      await mountLobby(tester, FakeSession(), size: size);
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('room-100001')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byType(LobbyRoomCard).hitTestable(), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('large text fits narrow screen', (tester) async {
    await mountLobby(
      tester,
      FakeSession(),
      size: const Size(360, 800),
      scale: 2,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
