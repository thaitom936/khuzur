import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'main_menu/main_menu_screen.dart';
import 'online/friends_screen.dart';
import 'online/online_screen.dart';
import 'online/rank_screen.dart';
import 'play_session/play_session_screen.dart';
import 'settings/settings_screen.dart';
import 'style/my_transition.dart';
import 'style/palette.dart';

/// The router describes the game's navigational hierarchy.
final router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const MainMenuScreen(key: Key('main menu')),
      routes: [
        GoRoute(
          path: 'play',
          pageBuilder: (context, state) => buildMyTransition<void>(
            key: const ValueKey('play'),
            color: context.watch<Palette>().backgroundPlaySession,
            child: const PlaySessionScreen(key: Key('play session')),
          ),
        ),
        GoRoute(
          path: 'online',
          builder: (context, state) =>
              const OnlineScreen(key: Key('online lobby')),
          routes: [
            GoRoute(
              path: 'table',
              pageBuilder: (context, state) => buildMyTransition<void>(
                key: const ValueKey('online table'),
                color: context.watch<Palette>().backgroundPlaySession,
                child: const OnlineTableScreen(key: Key('online table')),
              ),
            ),
            GoRoute(
              path: 'rank',
              builder: (context, state) => const RankScreen(key: Key('rank')),
            ),
            GoRoute(
              path: 'friends',
              builder: (context, state) =>
                  const FriendsScreen(key: Key('friends')),
            ),
          ],
        ),
        GoRoute(
          path: 'settings',
          builder: (context, state) =>
              const SettingsScreen(key: Key('settings')),
        ),
      ],
    ),
  ],
);
