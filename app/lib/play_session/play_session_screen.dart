/// The Muushig table (portrait). Works against the [GameController]
/// interface: local (vs bots) and online games share this screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../audio/audio_controller.dart';
import '../audio/sounds.dart';
import '../chat/chat_screen.dart';
import '../game/game_controller.dart';
import '../game/local_game.dart';
import '../game/remote_game.dart';
import '../game/replay_controller.dart';
import '../l10n/strings.dart';
import '../net/net_client.dart';
import '../rtc/table_call_controller.dart';
import '../rtc/table_call_widgets.dart';
import '../rules/card.dart' as rules;
import '../rules/mongol13.dart';
import '../rules/rules.dart';
import '../rules/thousand.dart';
import '../settings/settings.dart';
import '../style/confetti.dart';
import '../style/lobby_theme.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import 'card_widget.dart';
import 'hand_card_gesture.dart';
import 'spectator_controls.dart';
import 'table_motion.dart';
import 'turn_countdown_avatar.dart';

/// Single-player entry: owns a fresh [LocalGameController].
class PlaySessionScreen extends StatelessWidget {
  const PlaySessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GameController>(
      create: (_) => LocalGameController(),
      child: const TableView(),
    );
  }
}

/// Online entry: uses the app-wide [RemoteGameController].
class OnlineTableScreen extends StatelessWidget {
  const OnlineTableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final game = context.read<RemoteGameController>();
    return ChangeNotifierProvider<GameController>.value(
      value: game,
      child: ChangeNotifierProvider(
        create: (_) => TableCallController(
          game.session,
          game,
          onCallActive: context.read<AudioController>().setCallActive,
        ),
        child: const TableView(),
      ),
    );
  }
}

class TableView extends StatefulWidget {
  const TableView({super.key});

  @override
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView> {
  /// Cards selected in the hand (for exchanging, or the pending play).
  final Set<int> _selected = {};
  Phase? _lastPhase;
  Timer? _clock;
  int _shownPlayError = 0;
  int _durakTarget = 0;
  int _thousandChoice = 100;
  bool _leavingRoom = false;
  final _tableScaffold = GlobalKey<ScaffoldState>();
  bool _chatDrawerOpen = false, _quickChatOpen = false;

  @override
  void initState() {
    super.initState();
    // Ticks the turn-countdown display for online games.
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && context.read<GameController>().turnDeadline != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();
    final game = context.watch<GameController>();
    final l = L.of(context);
    if (game is RemoteGameController &&
        game.playErrorVersion != _shownPlayError) {
      _shownPlayError = game.playErrorVersion;
      final error = game.playError;
      if (error != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l('cardReturned')} ${l.error(error)}')),
          );
        });
      }
    }

    if (game.phase != _lastPhase) {
      _lastPhase = game.phase;
      _selected.clear();
    }

    final isReplay = game is ReplayController;
    final spectating = game is RemoteGameController && game.spectating;
    if (game is RemoteGameController && game.roomDissolved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        GoRouter.of(context).go('/online');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l('roomDissolved'))));
      });
      return const SizedBox.shrink();
    }

    return PopScope(
      canPop: game is! RemoteGameController,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave(game);
      },
      child: Scaffold(
        key: _tableScaffold,
        backgroundColor: palette.backgroundPlaySession,
        drawer: game is RemoteGameController ? _chatDrawer(game, l) : null,
        drawerScrimColor: Colors.black.withValues(alpha: .12),
        drawerEnableOpenDragGesture: false,
        onDrawerChanged: (open) {
          if (!mounted) return;
          setState(() => _chatDrawerOpen = open);
          if (!open) FocusScope.of(context).unfocus();
        },
        body: DecoratedBox(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/bg.jpg'),
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: _tableViewport(
              replay: isReplay,
              spectating: spectating,
              child: CardTableMotion(
                game: game,
                builder: (context, motion) => Stack(
                  children: [
                    _tableLayout(game, l, motion),
                    if (!isReplay &&
                        !motion.animating &&
                        game.phase == Phase.roundEnd)
                      _roundEndOverlay(game, l),
                    if (!isReplay &&
                        (!spectating ||
                            game.isMongol13 ||
                            game.isDurak ||
                            game.isThousand) &&
                        !motion.animating &&
                        game.phase == Phase.gameEnd)
                      _gameEndOverlay(game, l),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tableViewport({
    required bool replay,
    required bool spectating,
    required Widget child,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep cards and actions readable in short windows instead of letting
        // the centre overflow into the player's hand when they sit down.
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1, 2);
        final game = context.read<GameController>();
        final muushig = !game.isMongol13 && !game.isDurak && !game.isThousand;
        final call = context.watch<TableCallController?>();
        final hasVideo =
            muushig &&
            game.seats.any((s) => !s.bot && (call?.videoOn(s.rtcUid) ?? false));
        final videoWidth = (constraints.maxWidth.clamp(0, 760) * .24).clamp(
          80.0,
          112.0,
        );
        // Two portrait rows, a clear trick area and actions above the bottom hand.
        // Grow for accessibility; on short windows scroll instead of overlap.
        final minimumHeight =
            404 +
            (game is RemoteGameController ? 56 : 0) +
            (context.read<GameController>().isThousand ? 60 + 80 * scale : 0) +
            (replay || spectating
                    ? 218
                    : (context.read<GameController>().isDurak ||
                          context.read<GameController>().isThousand)
                    ? 248
                    : 200) *
                scale +
            2.36 * 88 +
            (muushig ? 32 * (scale - 1) : 0) +
            (hasVideo ? (videoWidth * 1.18 - 62) * 3 : 0);
        final table = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: child,
          ),
        );
        if (constraints.maxHeight >= minimumHeight) return table;
        return SingleChildScrollView(
          child: SizedBox(
            width: constraints.maxWidth,
            height: minimumHeight,
            child: table,
          ),
        );
      },
    );
  }

  Widget _replayControls(ReplayController game) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.skip_previous),
          onPressed: game.stepBack,
        ),
        IconButton(
          icon: Icon(game.autoPlay ? Icons.pause : Icons.play_arrow),
          onPressed: game.toggleAuto,
        ),
        IconButton(
          icon: const Icon(Icons.skip_next),
          onPressed: game.atEnd ? null : game.stepForward,
        ),
        const SizedBox(width: 12),
        Text('R${game.roundNo}'),
        if (game.desyncError != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              '⚠ ${game.desyncError}',
              style: const TextStyle(color: Colors.red, fontSize: 11),
            ),
          ),
      ],
    );
  }

  void _leave(GameController game) {
    if (_tableScaffold.currentState?.isDrawerOpen ?? false) {
      _tableScaffold.currentState?.closeDrawer();
      return;
    }
    if (game is RemoteGameController) {
      if (game.spectating) {
        game.unwatch();
        GoRouter.of(context).go('/online');
      } else if (game.started && !game.gameOver) {
        _confirmForfeit(game); // leaving mid-game forfeits the seat
      } else if (!game.started) {
        _confirmWaitingExit(game);
      } else {
        game.leaveRoom();
        GoRouter.of(context).go('/online');
      }
    } else if (game is ReplayController) {
      GoRouter.of(context).go('/online');
    } else {
      GoRouter.of(context).go('/');
    }
  }

  Future<void> _confirmWaitingExit(RemoteGameController game) async {
    if (_leavingRoom) return;
    _leavingRoom = true;
    final l = L(context.read<SettingsController>().lang.value);
    final host = game.humanSeat == 0;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l(host ? 'dissolveRoomTitle' : 'leaveRoomTitle')),
          content: Text(l(host ? 'dissolveRoomBody' : 'leaveRoomBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l(host ? 'dissolveRoom' : 'leaveBtn')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      if (host) {
        await game.dissolveRoom();
      } else {
        await game.session.client.call('leave_room');
        game.reset();
      }
      if (mounted) GoRouter.of(context).go('/online');
    } on NetException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.error(e.code))));
      }
    } finally {
      _leavingRoom = false;
    }
  }

  void _confirmForfeit(RemoteGameController game) {
    final l = L(context.read<SettingsController>().lang.value);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l('leaveTitle')),
        content: Text(l('leaveBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              game.abandon();
              GoRouter.of(context).go('/online');
            },
            child: Text(l('leaveBtn')),
          ),
        ],
      ),
    );
  }

  Widget _tableLayout(GameController game, L l, CardTableMotionState motion) {
    final spectating = game is RemoteGameController && game.spectating;
    final replay = game is ReplayController;
    final waiting = game is RemoteGameController && !game.started;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final muushig = !game.isMongol13 && !game.isDurak && !game.isThousand;
    final call = context.watch<TableCallController?>();
    // Muushig runs clockwise from the bottom centre in a 2-2-1 arrangement.
    // Spectators anchor the same arrangement on seat 0.
    final anchor = game.humanSeat >= 0 ? game.humanSeat : 0;
    final seatCount = waiting ? game.numPlayers : game.seats.length;
    final others = [
      for (var i = 1; i < seatCount; i++) (anchor + i) % seatCount,
    ];
    final positions = muushig && others.length == 4
        ? const [Offset(.84, 1), Offset(.74, 0), Offset(.26, 0), Offset(.16, 1)]
        : muushig && others.length == 3
        ? const [Offset(.84, 1), Offset(.74, 0), Offset(.26, 0)]
        : switch (others.length) {
            1 => const [Offset(.5, 0)],
            2 => const [Offset(.75, 0), Offset(.25, 0)],
            3 => const [Offset(.75, 0), Offset(.25, 0), Offset(.22, 1)],
            5 => const [
              Offset(.82, 0),
              Offset(.5, 0),
              Offset(.18, 0),
              Offset(.16, 1),
              Offset(.5, 1),
            ],
            _ => const [
              Offset(.82, 0),
              Offset(.5, 0),
              Offset(.18, 0),
              Offset(.22, 1),
            ],
          };
    return DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.white),
      child: IconTheme(
        data: const IconThemeData(color: Colors.white),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final footer =
                (spectating || replay
                    ? 74.0
                    : (game.isDurak || game.isThousand)
                    ? 104.0
                    : 56.0) *
                scale;
            final communicationSpace = game is RemoteGameController
                ? 56.0
                : 0.0;
            final seatWidth = muushig
                ? (constraints.maxWidth * .24).clamp(80.0, 112.0)
                : ((constraints.maxHeight -
                              404 -
                              communicationSpace -
                              (game.isThousand ? 60 + 80 * scale : 0) -
                              144 * scale -
                              footer) /
                          2.36)
                      .clamp(
                        88.0,
                        ((constraints.maxWidth - 48) / 3).clamp(88.0, 144.0),
                      );
            final hasVideo = game.seats.any(
              (s) => !s.bot && (call?.videoOn(s.rtcUid) ?? false),
            );
            final frameSize = Size(
              seatWidth,
              muushig && !hasVideo ? 62 : seatWidth * 1.18,
            );
            Size seatFrame(int seat) =>
                muushig &&
                    (seat >= game.seats.length ||
                        game.seats[seat].bot ||
                        !(call?.videoOn(game.seats[seat].rtcUid) ?? false))
                ? const Size(58, 62)
                : Size(seatWidth, seatWidth * 1.18);
            final seatHeight = frameSize.height + 12 + 32 * scale;
            // The surrounding SafeArea keeps the bottom hand off the home
            // indicator. Spectator/replay controls still have their own footer.
            final handBottom = spectating || replay ? footer + 12 : 12.0;
            final actionsBottom = handBottom + 144;
            final communicationBottom = spectating || replay
                ? actionsBottom
                : actionsBottom + footer;
            final ownBottom = communicationBottom + communicationSpace;
            final sideBottom = muushig
                ? ownBottom + seatHeight + 12
                : ownBottom;
            final topSeat = 60 * scale + 44;
            final centerTop = topSeat + seatHeight + 16;
            final twoLowerSeats = seatCount >= 4;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(top: 0, left: 0, right: 0, child: _topBar(game, l)),
                for (var i = 0; i < others.length; i++)
                  Positioned(
                    key: ValueKey('table-seat-${others[i]}'),
                    left:
                        constraints.maxWidth * positions[i].dx - seatWidth / 2,
                    top: positions[i].dy == 0 ? topSeat : null,
                    bottom: positions[i].dy == 1 ? sideBottom : null,
                    width: seatWidth,
                    child: motion.seat(
                      others[i],
                      _seatPanel(game, l, others[i], seatFrame(others[i])),
                    ),
                  ),
                Positioned(
                  key: const ValueKey('table-center'),
                  top: centerTop,
                  left: muushig ? 64 : 12,
                  right: 12,
                  height: game.isThousand
                      ? 180 + 100 * scale
                      : 120 + 20 * scale,
                  child: waiting
                      ? _waitingTableCenter(game, l)
                      : _center(game, l, motion),
                ),
                if (!waiting &&
                    !game.isMongol13 &&
                    !game.isDurak &&
                    !game.isThousand)
                  Positioned(
                    key: const ValueKey('table-stock'),
                    // A narrow left rail keeps trump/stock clear of videos,
                    // won-card headers and the central trick, even at 2x text.
                    top: centerTop - 12,
                    left: 12,
                    child: Semantics(
                      label:
                          '${l('trump')} ${suitSymbols[game.trumpSuit]}, ${l('stock')}: ${game.stockCount}',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CardView(game.trumpIndicatorCard, width: 36),
                          const SizedBox(height: 8),
                          motion.deck(width: 36, count: game.stockCount),
                        ],
                      ),
                    ),
                  ),
                if (game.seats.isNotEmpty)
                  Positioned(
                    key: ValueKey('table-seat-$anchor'),
                    left:
                        constraints.maxWidth *
                            (muushig
                                ? .5
                                : game.seats.length == 6
                                ? .84
                                : twoLowerSeats
                                ? .78
                                : .5) -
                        seatWidth / 2,
                    bottom: ownBottom,
                    width: seatWidth,
                    child: motion.seat(
                      anchor,
                      _seatPanel(game, l, anchor, seatFrame(anchor)),
                    ),
                  ),
                if (!spectating && !replay && !waiting)
                  Positioned(
                    key: const ValueKey('table-actions'),
                    right: 12,
                    left: 12,
                    bottom: actionsBottom,
                    child: IgnorePointer(
                      ignoring: motion.dealing,
                      child: _actions(game, l),
                    ),
                  ),
                if (game.autoPlaying)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: actionsBottom,
                    child: _autoBanner(game, l),
                  ),
                if (!waiting)
                  Positioned(
                    key: const ValueKey('table-hand'),
                    left: 14,
                    right: 14,
                    bottom: handBottom,
                    height: 132,
                    child: _hand(game, motion),
                  ),
                if (game is RemoteGameController)
                  Positioned(
                    left: 12,
                    bottom: communicationBottom,
                    child: _communicationBar(game, l),
                  ),
                if (spectating)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SpectatorControls(game: game),
                  ),
                if (replay)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _replayControls(game),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _waitingTableCenter(RemoteGameController game, L l) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(l('waitingFriends'), textAlign: TextAlign.center),
      if (!game.spectating)
        TextButton.icon(
          onPressed: () => _inviteFriends(game, l),
          icon: const Icon(Icons.person_add_alt, color: Colors.white, size: 18),
          label: Text(
            l('inviteFriends'),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      if (game.humanSeat == 0 &&
          !game.spectating &&
          (game.isThousand
              ? game.seats.length == 3
              : (game.isMongol13 || game.isDurak) && game.seats.length >= 2))
        TextButton(
          onPressed: () async {
            try {
              await game.session.client.call('start_room');
            } on NetException catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l.error(e.code))));
              }
            }
          },
          child: Text(
            l('m13Start'),
            style: const TextStyle(color: Colors.white),
          ),
        ),
    ],
  );

  Future<void> _inviteFriends(RemoteGameController game, L l) async {
    try {
      final response = await game.session.client.call('friends');
      final friends = (response['friends'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .where((f) => f['online'] == true)
          .toList();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: friends.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l.error('friend_offline')),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final friend in friends)
                      ListTile(
                        title: Text(friend['name'] as String),
                        trailing: TextButton(
                          child: Text(l('invite')),
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            try {
                              await game.session.client.call('invite', {
                                'uid': friend['uid'],
                              });
                            } on NetException catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l.error(e.code))),
                                );
                              }
                            }
                          },
                        ),
                      ),
                  ],
                ),
        ),
      );
    } on NetException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.error(e.code))));
      }
    }
  }

  Widget _chatDrawer(RemoteGameController game, L l) => LobbyTheme(
    child: Builder(
      builder: (context) => Drawer(
        key: const ValueKey('table-chat-drawer'),
        width: (MediaQuery.sizeOf(context).width - 32).clamp(0, 420),
        elevation: 0,
        backgroundColor: Theme.of(
          context,
        ).scaffoldBackgroundColor.withValues(alpha: .78),
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 4, top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l('tableChat'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!game.spectating && game.chatChannel != null)
                      IconButton(
                        key: const Key('table-chat-quick-toggle'),
                        tooltip: l('quickChat'),
                        onPressed: () =>
                            setState(() => _quickChatOpen = !_quickChatOpen),
                        icon: Icon(
                          _quickChatOpen
                              ? Icons.keyboard_arrow_up
                              : Icons.format_quote,
                        ),
                      ),
                    IconButton(
                      key: const Key('table-chat-close'),
                      tooltip: l('close'),
                      onPressed: () =>
                          _tableScaffold.currentState?.closeDrawer(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (!game.spectating &&
                  (_quickChatOpen || game.chatChannel == null))
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (var i = 0; i < l.phrases.length; i++)
                        TextButton(
                          child: Text(l.phrases[i]),
                          onPressed: () {
                            game.sendChat(i);
                            _tableScaffold.currentState?.closeDrawer();
                          },
                        ),
                    ],
                  ),
                ),
              if (game.chatChannel != null)
                Expanded(
                  child: ChatScreen(
                    key: ValueKey(game.chatChannel),
                    channel: game.chatChannel!,
                    title: l('tableChat'),
                    embedded: true,
                    translucent: true,
                    active: _chatDrawerOpen,
                    call: context.read<TableCallController?>(),
                  ),
                )
              else
                const Spacer(),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _topBar(GameController game, L l) {
    return SizedBox(
      height: 60 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
      child: Row(
        children: [
          IconButton(
            tooltip: l('back'),
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => _leave(game),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  game.roomCode == null
                      ? 'Muushig'
                      : '${game.isThousand
                            ? 'Thousand · '
                            : (game.isDurak || game.isThousand)
                            ? 'Durak'
                            : game.isMongol13
                            ? 'Mongol 13'
                            : l('tableLabel')} ${game.roomCode}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  game is RemoteGameController && !game.started
                      ? '${game.seats.length} / ${game.numPlayers}'
                      : '${l('round')} ${game.roundNo}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l('settings'),
            icon: const Icon(Icons.more_horiz),
            onPressed: () => GoRouter.of(context).push('/settings'),
          ),
        ],
      ),
    );
  }

  Widget _communicationBar(RemoteGameController game, L l) {
    return Padding(
      key: const ValueKey('table-communication-controls'),
      padding: const EdgeInsets.only(right: 4),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: const Color(0xff153d35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            IconButton(
              tooltip: l('tableChat'),
              icon: const Icon(Icons.forum_outlined),
              onPressed: () => _tableScaffold.currentState?.openDrawer(),
            ),
            if (!game.spectating) const TableCallButton(),
          ],
        ),
      ),
    );
  }

  String _seatName(GameController game, L l, int seat) {
    if (seat == game.humanSeat) return l('you');
    final s = seat < game.seats.length ? game.seats[seat] : null;
    if (s == null) return '?';
    return s.bot && game.isLocal ? '${l('bot')} $seat' : s.name;
  }

  Widget _seatPanel(GameController game, L l, int seat, Size frameSize) {
    if (seat >= game.seats.length) {
      return Column(
        key: ValueKey('table-empty-seat-$seat'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.fromSize(
            size: frameSize,
            child: const Center(
              child: CircleAvatar(
                radius: 23,
                backgroundColor: Colors.white12,
                child: Icon(Icons.person_add_alt, color: Colors.white54),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l('openSeat'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 14),
        ],
      );
    }
    final s = game.seats[seat];
    final waiting = game is RemoteGameController && !game.started;
    final active =
        !waiting &&
        (game.phase == Phase.deciding && game.simultaneousDecisions
            ? s.decision == Decision.none
            : game.turn == seat) &&
        game.phase != Phase.roundEnd &&
        game.phase != Phase.gameEnd;
    final name = game.isLocal ? _seatName(game, l, seat) : s.name;
    final bubble = game.chatBubbles[seat];
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final compact = frameSize.width == 58;
    final call = context.watch<TableCallController?>();
    final canOpenCall =
        game is RemoteGameController &&
        !game.spectating &&
        seat == game.humanSeat &&
        call != null;
    // Rule: players who passed sit this round out, dimmed, score unchanged.
    return Opacity(
      opacity: s.decision == Decision.pass || s.finished ? 0.45 : 1,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          if (!waiting && s.wonCards.isNotEmpty)
            Positioned(
              top: -40,
              left: 0,
              right: 0,
              child: FittedBox(
                key: ValueKey('won-cards-$seat'),
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final card in s.wonCards)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: CardView(card, width: 22),
                      ),
                  ],
                ),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                key: ValueKey('seat-call-control-$seat'),
                behavior: HitTestBehavior.opaque,
                onTap: canOpenCall
                    ? () => showTableCallPanel(context, call)
                    : null,
                child: SizedBox(
                  width: frameSize.width,
                  height: frameSize.height,
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: TurnCountdownAvatar(
                          name: s.name,
                          frameSize: compact ? null : frameSize,
                          avatar: CallAvatar(
                            name: s.name,
                            uid: game is RemoteGameController && !s.bot
                                ? s.rtcUid
                                : null,
                            portrait: !compact,
                            size: compact
                                ? const Size.square(46)
                                : Size(
                                    frameSize.width - 8,
                                    frameSize.height - 8,
                                  ),
                          ),
                          active:
                              game is! ReplayController &&
                              active &&
                              (seat != game.humanSeat || game.humanTurn),
                          deadline: game.turnDeadline,
                          duration: game.turnDuration,
                          turnLabel: l('yourTurn'),
                        ),
                      ),
                      if (!waiting)
                        Positioned(
                          right: compact ? 0 : 10,
                          bottom: compact ? 8 : 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .9),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '${game.isMongol13 || game.isDurak ? s.handCount : s.score}',
                              style: const TextStyle(
                                color: Color(0xff244b43),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      if (!waiting &&
                          !game.isMongol13 &&
                          !game.isDurak &&
                          seat == game.dealer)
                        Positioned(
                          left: compact ? 0 : 10,
                          top: compact ? 0 : 10,
                          child: const CircleAvatar(
                            radius: 10,
                            backgroundColor: Color(0xffe3f5f1),
                            child: Text(
                              'D',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xff244b43),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: compact ? 4 : 12),
              SizedBox(
                height: 18 * scale,
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, height: 1.2),
                ),
              ),
              SizedBox(
                height: 14 * scale,
                child: Text(
                  s.finished
                      ? l('durakOut')
                      : s.decision == Decision.pass
                      ? l('passed')
                      : !s.online && !s.bot
                      ? l('offline')
                      : ' ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          if (bubble != null)
            Positioned(
              left: 0,
              right: 0,
              top: frameSize.height * .4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  bubble < l.phrases.length ? l.phrases[bubble] : '…',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xff244b43),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _countdown(GameController game) {
    final deadline = game.turnDeadline;
    if (deadline == null) return '';
    final left = deadline.difference(DateTime.now()).inSeconds;
    return left > 0 ? ' ($left)' : '';
  }

  Widget _center(GameController game, L l, CardTableMotionState motion) {
    if (game is RemoteGameController && game.isDurak) {
      return _durakCenter(game, l, motion);
    }
    // Rule: centre cards are shown smallest to largest, without names.
    final trick = [...game.displayTrick]
      ..sort(
        (a, b) => rules.rankOf(a.card) != rules.rankOf(b.card)
            ? rules.rankOf(a.card) - rules.rankOf(b.card)
            : a.card - b.card,
      );
    final String status;
    if (game is RemoteGameController && game.isThousand) {
      status = game.thousandStage == 'bid'
          ? l('thousandBidHint')
          : game.thousandStage == 'give'
          ? l('thousandGiveHint')
          : game.thousandStage == 'contract'
          ? l('thousandContractHint')
          : game.humanTurn
          ? l('yourTurn') + _countdown(game)
          : l.fmt('thinking', _seatName(game, l, game.turn)) + _countdown(game);
    } else if (game.isMongol13 && game.humanTurn) {
      status = game.openingCard != null
          ? '${l('m13Opening')} ${rankLabel(game.openingCard!)}${suitSymbols[rules.suitOf(game.openingCard!)]}'
          : l('m13Select') + _countdown(game);
    } else if (game.phase == Phase.deciding && game.simultaneousDecisions) {
      status =
          l(game.humanTurn ? 'decideHint' : 'waitingDecisions') +
          _countdown(game);
    } else if (game.completedTrickWinner != null) {
      status = l.fmt(
        'takesTrick',
        _seatName(game, l, game.completedTrickWinner!),
      );
    } else if (game.humanTurn) {
      status = switch (game.phase) {
        Phase.deciding => l('decideHint'),
        Phase.exchanging => l.fmt('exchangeHint', game.maxExchangeNow),
        Phase.navsh => l('takeHint'),
        Phase.playing => l('yourTurn') + _countdown(game),
        _ => '',
      };
    } else if (game.turn >= 0 &&
        game.turn < game.seats.length &&
        (game.phase == Phase.deciding ||
            game.phase == Phase.exchanging ||
            game.phase == Phase.navsh ||
            game.phase == Phase.playing)) {
      status =
          l.fmt('thinking', _seatName(game, l, game.turn)) + _countdown(game);
    } else {
      status = '';
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (game is RemoteGameController && game.isThousand) ...[
          Text(
            '${l('thousandContract')} ${game.thousandStage == 'bid' ? game.thousandBid : game.thousandContract} · ${_seatName(game, l, game.thousandBidder)}',
            textAlign: TextAlign.center,
          ),
          Text(
            game.trumpSuit < 0
                ? l('thousandNoTrump')
                : '${l('trump')} ${suitSymbols[game.trumpSuit]}',
          ),
          if (game.thousandStage == 'give' || game.thousandStage == 'contract')
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final c in game.thousand['kitty'] as List? ?? [])
                  Padding(
                    padding: const EdgeInsets.all(3),
                    child: CardView(rules.parseCard(c as String), width: 36),
                  ),
              ],
            ),
          if (game.humanSeat >= 0 &&
              (game.thousand['details'] as List? ?? []).length > game.humanSeat)
            Text(
              '${l('thousandPoints')} ${(game.thousand['details'] as List)[game.humanSeat]['points']} + ${(game.thousand['details'] as List)[game.humanSeat]['bonus']}'
              '${(game.thousand['details'] as List)[game.humanSeat]['barrel'] == true ? ' · ${l('thousandBarrel')} ${(game.thousand['details'] as List)[game.humanSeat]['attempts']}/3' : ''}',
            ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height:
              game is RemoteGameController &&
                  game.isThousand &&
                  game.thousandStage != 'play'
              ? 0
              : 96,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final t in trick)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        motion.trickCard(t.card, CardView(t.card, width: 58)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: Text(
            game.isMongol13 && trick.isNotEmpty
                ? '${l('m13_${m13Combo(trick.map((t) => t.card).toList())?.kind ?? 'single'}')} · $status'
                : status,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _durakCenter(
    RemoteGameController game,
    L l,
    CardTableMotionState motion,
  ) {
    final pairs = game.displayDurakPairs;
    if (!game.playPending &&
        (_durakTarget >= pairs.length ||
            (pairs.isNotEmpty && pairs[_durakTarget].cover != null))) {
      _durakTarget = pairs.indexWhere((p) => p.cover == null);
      if (_durakTarget < 0) _durakTarget = 0;
    }
    final stage = game.durakStage;
    final status = game.humanTurn
        ? l(
            stage == 'defend'
                ? 'durakChooseTarget'
                : stage == 'add'
                ? 'durakAddHint'
                : 'durakAttackHint',
          )
        : game.turn >= 0 && game.turn < game.seats.length
        ? l.fmt('thinking', _seatName(game, l, game.turn))
        : '';
    return Column(
      children: [
        SizedBox(
          height: 34,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CardView(game.trumpCard, width: 20),
              const SizedBox(width: 6),
              motion.deck(width: 20, count: game.stockCount),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${l('trump')} ${suitSymbols[game.trumpSuit]} · ${l('stock')}: ${game.stockCount}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = pairs.isEmpty
                  ? 40.0
                  : ((constraints.maxWidth / pairs.length) - 6).clamp(
                      20.0,
                      46.0,
                    );
              return FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < pairs.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: GestureDetector(
                          onTap: pairs[i].cover == null
                              ? () => setState(() => _durakTarget = i)
                              : null,
                          child: Container(
                            key: ValueKey('durak-pair-$i'),
                            width: width + 4,
                            height: width * 1.5 + 28,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color:
                                    game.humanTurn &&
                                        stage == 'defend' &&
                                        i == _durakTarget
                                    ? Colors.white
                                    : Colors.transparent,
                              ),
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  child: motion.trickCard(
                                    pairs[i].attack,
                                    CardView(pairs[i].attack, width: width),
                                  ),
                                ),
                                if (pairs[i].cover != null)
                                  Positioned(
                                    top: 24,
                                    left: 4,
                                    child: motion.trickCard(
                                      pairs[i].cover!,
                                      CardView(pairs[i].cover!, width: width),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: 32,
          child: Text(
            '${game.durak['taking'] == true ? '${l('durakTaking')} · ' : ''}$status${_countdown(game)}',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _autoBanner(GameController game, L l) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Tooltip(
          message: l('autoOn'),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xff153d35),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_toy_outlined, color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: _tableButton(
            onPressed: () => game.setAuto(false),
            child: Text(l('autoOff')),
          ),
        ),
      ],
    );
  }

  Widget _hand(GameController game, CardTableMotionState motion) {
    final hand = [...game.displayHand]
      ..sort(
        (a, b) => game.isThousand
            ? (rules.suitOf(a) != rules.suitOf(b)
                  ? rules.suitOf(a).compareTo(rules.suitOf(b))
                  : thousandStrength(a).compareTo(thousandStrength(b)))
            : game.isMongol13
            ? m13Value(a).compareTo(m13Value(b))
            : a.compareTo(b),
      );
    _selected.removeWhere((c) => !hand.contains(c));
    final playing = game.phase == Phase.playing && game.humanTurn;
    final exchanging =
        (game.phase == Phase.exchanging || game.phase == Phase.navsh) &&
        game.humanTurn;
    final legal = playing ? game.legalCards() : hand;
    Widget handCard(int card, double width) => HandCardGesture(
      onPlay:
          playing &&
              !motion.dealing &&
              !game.playPending &&
              !game.autoPlaying &&
              legal.contains(card) &&
              (game is! RemoteGameController ||
                  !game.isThousand ||
                  game.thousandStage == 'play')
          ? () => _playCards(
              game,
              _selected.contains(card) ? _selected.toList() : [card],
            )
          : null,
      child: motion.handCard(
        card,
        CardView(
          card,
          width: width,
          selected: _selected.contains(card),
          disabled:
              game.playPending ||
              game.autoPlaying ||
              (playing && !legal.contains(card)),
          onTap: motion.dealing
              ? null
              : () => _onCardTap(
                  game,
                  card,
                  playing: playing,
                  exchanging: exchanging,
                ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (hand.isEmpty) return const SizedBox.shrink();
        if (game.isDurak && hand.length > 15) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final c in hand)
                  Padding(
                    key: ValueKey('hand-card-$c'),
                    padding: const EdgeInsets.fromLTRB(0, 12, 6, 12),
                    child: handCard(c, 64),
                  ),
              ],
            ),
          );
        }
        final width = constraints.maxWidth.clamp(0.0, 80.0);
        final stride = hand.length <= 1
            ? 0.0
            : ((constraints.maxWidth - width) / (hand.length - 1)).clamp(
                0.0,
                width + 6,
              );
        return Center(
          child: SizedBox(
            width: width + stride * (hand.length - 1),
            height: 132,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < hand.length; i++)
                  Positioned(
                    key: ValueKey('hand-card-${hand[i]}'),
                    left: i * stride,
                    top: 12,
                    child: handCard(hand[i], width),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onCardTap(
    GameController game,
    int card, {
    required bool playing,
    required bool exchanging,
  }) {
    if (game.playPending || game.autoPlaying) return;
    if (playing) {
      if (game.isThousand) {
        setState(() {
          if (!_selected.remove(card)) {
            _selected.clear();
            _selected.add(card);
          }
        });
        return;
      }
      if (game is RemoteGameController && game.isDurak) {
        setState(() {
          if (!_selected.remove(card)) {
            if (game.durakStage == 'defend') _selected.clear();
            if (_selected.length < 6) _selected.add(card);
          }
        });
        return;
      }
      if (game.isMongol13) {
        setState(() {
          if (!_selected.remove(card) && _selected.length < 5) {
            _selected.add(card);
          }
        });
        return;
      }
      setState(() {
        if (!_selected.remove(card)) {
          _selected
            ..clear()
            ..add(card);
        }
      });
    } else if (exchanging) {
      setState(() {
        if (!_selected.remove(card)) {
          if (game.phase == Phase.navsh) {
            _selected
              ..clear()
              ..add(card); // navsh trades exactly one card
          } else if (_selected.length < game.maxExchangeNow) {
            _selected.add(card);
          }
        }
      });
    }
  }

  void _playCards(
    GameController game,
    List<int> cards, {
    bool announce = false,
  }) {
    if (!game.humanTurn ||
        game.phase != Phase.playing ||
        game.autoPlaying ||
        game.playPending ||
        cards.isEmpty ||
        !cards.every(game.hand.contains)) {
      return;
    }
    if (game is RemoteGameController && game.isThousand) {
      if (game.thousandStage != 'play') return;
      game.thousandAction(
        'play',
        value: rules.cardString(cards.first),
        announce: announce,
      );
    } else if (game is RemoteGameController && game.isDurak) {
      final defending = game.durakStage == 'defend';
      game.durakAction(
        defending ? 'defend' : 'attack',
        cards: cards,
        target: defending ? _durakTarget : null,
      );
    } else if (game is RemoteGameController && game.isMongol13) {
      context.read<AudioController>().playSfx(SfxType.huhsh);
      game.playCombo(cards);
    } else {
      context.read<AudioController>().playSfx(SfxType.huhsh);
      game.play(rules.cardString(cards.first));
    }
    setState(_selected.clear);
  }

  Widget _actions(GameController game, L l) {
    if (!game.humanTurn || game.autoPlaying) return const SizedBox.shrink();
    final audio = context.read<AudioController>();

    if (game is RemoteGameController && game.isThousand) {
      if (game.thousandStage == 'bid' || game.thousandStage == 'contract') {
        final bidding = game.thousandStage == 'bid';
        final min = bidding ? game.thousandBid + 5 : game.thousandBid;
        final max = thousandBidCap(game.hand) < min
            ? min
            : thousandBidCap(game.hand);
        final canBid = !bidding || thousandBidCap(game.hand) >= min;
        final choice = _thousandChoice.clamp(min, max);
        return _actionRow([
          DropdownButton<int>(
            value: choice,
            isExpanded: true,
            items: [
              for (var n = min; n <= max; n += 5)
                DropdownMenuItem(value: n, child: Text('$n')),
            ],
            onChanged: (v) => setState(() => _thousandChoice = v ?? min),
          ),
          if (bidding)
            _tableButton(
              danger: true,
              onPressed: () => game.thousandAction('pass'),
              child: Text(l('m13Pass')),
            ),
          _tableButton(
            onPressed: canBid
                ? () => game.thousandAction(
                    bidding ? 'bid' : 'contract',
                    value: choice,
                  )
                : null,
            child: Text(l(bidding ? 'thousandBid' : 'thousandConfirm')),
          ),
        ]);
      }
      if (game.thousandStage == 'give') {
        final selected = _selected.toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_seatName(game, l, (game.humanSeat + 1) % 3)} ← ${selected.isNotEmpty ? rules.cardString(selected[0]) : '—'} · ${_seatName(game, l, (game.humanSeat + 2) % 3)} ← ${selected.length > 1 ? rules.cardString(selected[1]) : '—'}',
              maxLines: 2,
              textAlign: TextAlign.center,
            ),
            _tableButton(
              onPressed: selected.length == 2
                  ? () {
                      game.thousandAction(
                        'give',
                        value: selected.map(rules.cardString).toList(),
                      );
                      setState(_selected.clear);
                    }
                  : null,
              child: Text(l('thousandGive')),
            ),
          ],
        );
      }
      final chosen = _selected.firstOrNull;
      void play(bool announce) {
        if (chosen == null) return;
        _playCards(game, [chosen], announce: announce);
      }

      return _actionRow([
        _tableButton(
          onPressed: () => setState(() {
            final legal = game.legalCards()
              ..sort(
                (a, b) => thousandStrength(a).compareTo(thousandStrength(b)),
              );
            _selected
              ..clear()
              ..add(legal.first);
          }),
          child: Text(l('m13Hint')),
        ),
        _tableButton(
          onPressed: chosen != null && game.canAnnounceThousand(chosen)
              ? () => play(true)
              : null,
          child: Text(l('thousandAnnounce')),
        ),
        _tableButton(
          onPressed: chosen != null ? () => play(false) : null,
          child: Text(l('m13Play')),
        ),
      ]);
    }
    if (game is RemoteGameController && game.isDurak) {
      final defending = game.durakStage == 'defend';
      final canTransfer =
          defending &&
          game.durak['transfer'] == true &&
          game.durakPairs.every((p) => p.cover == null);
      void send(String action) {
        game.durakAction(
          action,
          cards: _selected.toList(),
          target: action == 'defend' ? _durakTarget : null,
        );
        setState(_selected.clear);
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canTransfer)
            TextButton(
              onPressed: _selected.length == 1 ? () => send('transfer') : null,
              child: Text(l('durakTransfer')),
            ),
          _actionRow([
            _tableButton(
              onPressed: () => setState(() {
                final hint = game.durakSuggestion();
                _selected
                  ..clear()
                  ..addAll(hint.cards);
                _durakTarget = hint.target ?? _durakTarget;
              }),
              child: Text(l('m13Hint')),
            ),
            _tableButton(
              danger: true,
              onPressed: defending || game.durakStage == 'add'
                  ? () => game.durakAction(defending ? 'take' : 'finish')
                  : null,
              child: Text(l(defending ? 'durakTake' : 'durakFinish')),
            ),
            _tableButton(
              onPressed: _selected.isNotEmpty
                  ? () => _playCards(game, _selected.toList())
                  : null,
              child: Text(l(defending ? 'durakDefend' : 'm13Play')),
            ),
          ]),
        ],
      );
    }
    if (game is RemoteGameController && game.isMongol13) {
      return _actionRow([
        _tableButton(
          onPressed: () => setState(() {
            _selected
              ..clear()
              ..addAll(game.comboHint());
          }),
          child: Text(l('m13Hint')),
        ),
        _tableButton(
          onPressed: game.passAllowed
              ? () {
                  game.decide(false);
                  setState(_selected.clear);
                }
              : null,
          danger: true,
          child: Text(l('m13Pass')),
        ),
        _tableButton(
          onPressed: _selected.isNotEmpty
              ? () => _playCards(game, _selected.toList())
              : null,
          child: Text(l('m13Play')),
        ),
      ]);
    }

    switch (game.phase) {
      case Phase.deciding:
        return _actionRow([
          _tableButton(
            onPressed: () {
              audio.playSfx(SfxType.buttonTap);
              game.decide(true);
            },
            child: Text(l('playBtn')),
          ),
          _tableButton(
            danger: true,
            onPressed: game.passAllowed
                ? () {
                    audio.playSfx(SfxType.buttonTap);
                    game.decide(false);
                  }
                : null,
            child: Text(l('passBtn')),
          ),
        ]);
      case Phase.exchanging:
        return _actionRow([
          _tableButton(
            onPressed: () {
              audio.playSfx(SfxType.buttonTap);
              game.exchange(const []);
              setState(_selected.clear);
            },
            child: Text(l('keepAll')),
          ),
          _tableButton(
            onPressed:
                _selected.isNotEmpty && _selected.length <= game.maxExchangeNow
                ? () {
                    audio.playSfx(SfxType.buttonTap);
                    game.exchange(_selected.map(rules.cardString).toList());
                    setState(_selected.clear);
                  }
                : null,
            child: Text(
              _selected.isEmpty
                  ? l('exchangeN')
                  : '${l('exchangeN')} ${_selected.length}',
            ),
          ),
        ]);
      case Phase.navsh:
        // Second exchange round: the dealer may trade the selected card
        // for the face-up trump.
        return _actionRow([
          _tableButton(
            onPressed: _selected.length == 1
                ? () {
                    audio.playSfx(SfxType.buttonTap);
                    game.takeTrump(rules.cardString(_selected.first));
                    setState(_selected.clear);
                  }
                : null,
            child: Text(
              '${l('takeTrumpBtn')} '
              '${rankLabel(game.trumpCard)}${suitSymbols[rules.suitOf(game.trumpCard)]}',
            ),
          ),
          _tableButton(
            danger: true,
            onPressed: () {
              audio.playSfx(SfxType.buttonTap);
              game.skipNavsh();
              setState(_selected.clear);
            },
            child: Text(l('navshSkip')),
          ),
        ]);
      case Phase.playing:
        return _tableButton(
          onPressed: _selected.isNotEmpty && !game.playPending
              ? () => _playCards(game, _selected.toList())
              : null,
          child: Text(l('m13Play')),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _actionRow(List<Widget> buttons) => Row(
    children: [
      for (var i = 0; i < buttons.length; i++) ...[
        if (i > 0) const SizedBox(width: 12),
        Expanded(child: buttons[i]),
      ],
    ],
  );

  Widget _tableButton({
    required Widget child,
    required VoidCallback? onPressed,
    bool danger = false,
  }) => FilledButton(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      backgroundColor: danger ? const Color(0xffef5350) : Colors.white,
      foregroundColor: danger ? Colors.white : const Color(0xff008f83),
      disabledBackgroundColor: Colors.white24,
      disabledForegroundColor: Colors.white54,
      shape: const StadiumBorder(),
    ),
    onPressed: onPressed,
    child: child,
  );

  Widget _scoreTable(GameController game, L l) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var seat = 0; seat < game.seats.length; seat++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 90, child: Text(_seatName(game, l, seat))),
                SizedBox(
                  width: 80,
                  child: Text(
                    game.isMongol13 || game.isDurak
                        ? '${l('m13Remaining')} ${game.seats[seat].handCount}'
                        : game.seats[seat].decision == Decision.pass
                        ? l('passed')
                        : '${game.seats[seat].tricks} ${l('tricksN')}',
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    '${l('score')} ${game.seats[seat].score}',
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _overlay(List<Widget> children) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black38,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundEndOverlay(GameController game, L l) {
    return _overlay([
      Text(
        l.fmt('roundFinished', game.roundNo),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      _scoreTable(game, l),
      const SizedBox(height: 16),
      if (game.isLocal)
        MyButton(onPressed: game.nextRound, child: Text(l('nextRound')))
      else
        Text(l('nextRoundSoon')),
    ]);
  }

  Widget _gameEndOverlay(GameController game, L l) {
    final winners = game.winners ?? const [];
    final humanWon = winners.contains(game.humanSeat);
    return Stack(
      children: [
        _overlay([
          Text(
            game is RemoteGameController && game.drawn
                ? l('durakDraw')
                : humanWon
                ? l('youWin')
                : l('gameOver'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (!(game is RemoteGameController && game.drawn))
            Text(
              '${l('winner')}: ${winners.map((s) => _seatName(game, l, s)).join(', ')}',
            ),
          if (game is RemoteGameController && game.isMongol13 && game.dragon)
            Text(l('m13Dragon')),
          if (game is RemoteGameController &&
              game.winnings[game.humanSeat] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l.fmt('wonCoins', game.winnings[game.humanSeat]!),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          const SizedBox(height: 12),
          _scoreTable(game, l),
          const SizedBox(height: 16),
          if (game is RemoteGameController &&
              (game.isDurak || game.isThousand) &&
              game.humanSeat == 0)
            MyButton(
              onPressed: game.restarting ? null : game.restartDurak,
              child: Text(l('nextRound')),
            ),
          MyButton(onPressed: () => _leave(game), child: Text(l('backToMenu'))),
        ]),
        if (humanWon)
          Positioned.fill(
            child: IgnorePointer(child: Confetti(isStopped: false)),
          ),
      ],
    );
  }
}
