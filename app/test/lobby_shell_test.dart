import 'dart:async';

import 'package:card/chat/clubs_screen.dart';
import 'package:card/game/remote_game.dart';
import 'package:card/net/net_client.dart';
import 'package:card/net/session.dart';
import 'package:card/online/online_screen.dart';
import 'package:card/settings/persistence/memory_settings_persistence.dart';
import 'package:card/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'smoke_test.dart' show FakeClient, FakeSession, mountLobby, room;

class ShellClient extends FakeClient {
  bool joined = false, expired = false;
  int messageId = 0;
  @override
  Future<Map<String, dynamic>> call(
    String cmd, [
    Map<String, dynamic>? args,
  ]) async {
    if (!cmd.startsWith('chat_') && !cmd.startsWith('club_')) {
      return super.call(cmd, args);
    }
    commands.add(cmd);
    requests.add({'cmd': cmd, ...?args});
    switch (cmd) {
      case 'chat_open':
        return {
          'messages': [],
          'capabilities': {'write': true, 'media': false},
        };
      case 'chat_send':
        return {
          'message': {
            'id': ++messageId,
            'uid': 1,
            'nonce': args!['nonce'],
            'body': args['body'],
            'name': 'Player',
          },
        };
      case 'club_list':
        return {
          'clubs': [
            {'id': 7, 'name': 'Grassland', 'members': 2},
            {'id': 99, 'name': 'Do not list this club', 'members': 3},
          ],
          'member': joined ? {'club_id': 7, 'role': 'member'} : null,
        };
      case 'club_invite_info':
        if (expired) throw NetException('club_invite_expired');
        return {
          'club': {'id': 7, 'name': 'Grassland'},
          'inviter': 'Bataa',
          'expires_at': 2000000000,
        };
      case 'club_join':
        joined = true;
        return {};
      case 'club_info':
        return {
          'club': {'id': 7, 'name': 'Grassland', 'description': ''},
          'members': [],
          'member': {'club_id': 7, 'role': 'member'},
        };
      default:
        return {};
    }
  }
}

class ShellSession extends FakeSession {
  final shell = ShellClient();
  @override
  FakeClient get client => shell;
}

void main() {
  testWidgets('Creating a waiting room navigates straight to its table', (
    tester,
  ) async {
    final session = ShellSession();
    final game = RemoteGameController(session);
    final router = GoRouter(
      initialLocation: '/online',
      routes: [
        GoRoute(
          path: '/online',
          builder: (_, _) => const OnlineScreen(),
          routes: [
            GoRoute(
              path: 'table',
              builder: (_, _) => const Scaffold(body: Text('Entered table')),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider(
            create: (_) =>
                SettingsController(store: MemoryOnlySettingsPersistence()),
          ),
          ChangeNotifierProvider<Session>.value(value: session),
          ChangeNotifierProvider<RemoteGameController>.value(value: game),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create and enter'));
    await tester.pumpAndSettle();
    session.shell.events.add({
      'push': 'room_update',
      'code': '123456',
      'game_type': 'muushig',
      'size': 5,
      'seats': [
        {'name': 'Player'},
      ],
    });
    await tester.pumpAndSettle();
    expect(game.started, isFalse);
    expect(find.text('Entered table'), findsOneWidget);
    expect(session.shell.commands, isNot(contains('start_room')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    game.dispose();
    session.dispose();
    await session.shell.events.close();
  });
  testWidgets(
    'Three tabs keep filters and drafts with clubs hidden and account actions in profile',
    (tester) async {
      final session = ShellSession();
      await mountLobby(tester, session);
      expect(find.byType(NavigationDestination), findsNWidgets(3));
      expect(find.text('Clubs'), findsNothing);
      expect(find.byType(ClubsScreen), findsNothing);
      expect(find.text('Coins'), findsNothing);
      expect(find.byTooltip('Daily rewards'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('game-filter-durak')));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('chat-input')),
        'unsent draft',
      );
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pumpAndSettle();
      expect(find.text('Coins'), findsOneWidget);
      expect(find.text('Player'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chat-input')))
            .controller!
            .text,
        'unsent draft',
      );
      expect(session.shell.commands.where((c) => c == 'chat_send'), isEmpty);
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('game-filter-durak')))
            .selected,
        isTrue,
      );
      expect(find.byKey(const ValueKey('room-100001')), findsNothing);
      expect(
        session.shell.commands.where((c) => c.startsWith('club_')),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Public visibility is explicit and creation waits for final confirmation',
    (tester) async {
      final session = ShellSession();
      await mountLobby(tester, session);
      await tester.tap(find.text('Create room'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Durak'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Public'));
      await tester.tap(find.byKey(const ValueKey('create-seats-3')));
      expect(session.shell.commands, isNot(contains('create_room')));
      await tester.tap(find.text('Create and enter'));
      await tester.pumpAndSettle();
      final request = session.shell.requests.lastWhere(
        (r) => r['cmd'] == 'create_room',
      );
      expect(request['locked'], isFalse);
      expect(request['size'], 3);
      expect(request['game_type'], 'durak');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Club is invite-only, preview and explicit confirmation precede join',
    (tester) async {
      final session = ShellSession();
      await session.ensureOnline();
      await mountLobby(tester, session, home: const ClubsScreen());
      await tester.pumpAndSettle();
      expect(find.text('Do not list this club'), findsNothing);
      expect(find.text('Search clubs'), findsNothing);
      await tester.tap(find.text('Enter invitation code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'a' * 32);
      await tester.tap(find.text('View invitation'));
      await tester.pumpAndSettle();
      expect(find.text('Invited by Bataa'), findsOneWidget);
      expect(session.shell.commands, isNot(contains('club_join')));
      await tester.tap(find.text('Confirm and join'));
      await tester.pumpAndSettle();
      expect(
        session.shell.requests.lastWhere(
          (r) => r['cmd'] == 'club_join',
        )['token'],
        'a' * 32,
      );
      expect(find.byType(ClubScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Expired invitation cannot join a club', (tester) async {
    final session = ShellSession()..shell.expired = true;
    await session.ensureOnline();
    await mountLobby(tester, session, home: const ClubsScreen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter invitation code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'a' * 32);
    await tester.tap(find.text('View invitation'));
    await tester.pumpAndSettle();
    expect(
      find.text('Invitation expired or invalid. Ask the owner for a new one.'),
      findsOneWidget,
    );
    expect(session.shell.commands, isNot(contains('club_join')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Lobby scroll position survives switching tabs', (tester) async {
    final session = ShellSession();
    session.shell.pending = Completer<Map<String, dynamic>>()
      ..complete({'rooms': List.generate(20, (i) => room('${200000 + i}'))});
    await mountLobby(tester, session);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    final before = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .pixels;
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();
    final after = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .pixels;
    expect(after, before);
    expect(after, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });
}
