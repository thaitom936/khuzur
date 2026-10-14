/// The Muushig table (portrait). Works against the [GameController]
/// interface: local (vs bots) and online games share this screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../audio/audio_controller.dart';
import '../audio/sounds.dart';
import '../game/game_controller.dart';
import '../game/local_game.dart';
import '../game/remote_game.dart';
import '../game/replay_controller.dart';
import '../l10n/strings.dart';
import '../rtc/table_call_controller.dart';
import '../rtc/table_call_widgets.dart';
import '../rules/card.dart' as rules;
import '../rules/mongol13.dart';
import '../rules/rules.dart';
import '../rules/thousand.dart';
import '../settings/settings.dart';
import '../style/confetti.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/player_avatar.dart';
import 'card_widget.dart';
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

    if (game is RemoteGameController && !game.started) {
      return Scaffold(
        backgroundColor: palette.backgroundMain,
        appBar: AppBar(
          title: Text(
            '${game.isThousand
                ? 'Thousand · '
                : (game.isDurak || game.isThousand)
                ? 'Durak · '
                : game.isMongol13
                ? 'Mongol 13 · '
                : ''}${game.roomCode ?? l('waitingFriends')}',
          ),
          leading: IconButton(
            tooltip: l('back'),
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _leave(game),
          ),
        ),
        body: ListView(
          children: [
            for (final seat in game.seats)
              ListTile(
                leading: PlayerAvatar(name: seat.name),
                title: Text(seat.name),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: game.spectating
              ? SpectatorControls(game: game)
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l('waitingFriends')),
                      if (game.humanSeat == 0 &&
                          (game.isThousand
                              ? game.seats.length == 3
                              : (!(game.isMongol13 || game.isDurak) ||
                                    game.seats.length >= 2)))
                        FilledButton(
                          onPressed: () async {
                            try {
                              await game.session.client.call('start_room');
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l.error('generic'))),
                                );
                              }
                            }
                          },
                          child: Text(
                            l(
                              game.isMongol13 || game.isDurak || game.isThousand
                                  ? 'm13Start'
                                  : 'startNow',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: palette.backgroundPlaySession,
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
        // Two portrait rows, a clear trick area, hand and a bottom action bar.
        // Grow for accessibility; on short windows scroll instead of overlap.
        final minimumHeight =
            404 +
            (context.read<GameController>().isThousand ? 60 + 80 * scale : 0) +
            (replay || spectating
                    ? 218
                    : (context.read<GameController>().isDurak ||
                          context.read<GameController>().isThousand)
                    ? 248
                    : 200) *
                scale +
            2.36 * 88;
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
    if (game is RemoteGameController) {
      if (game.spectating) {
        game.unwatch();
        GoRouter.of(context).go('/online');
      } else if (game.started && !game.gameOver) {
        _confirmForfeit(game); // leaving mid-game forfeits the seat
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
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    // Clockwise from the viewer at the lower right: three upper seats and one
    // lower-left neighbour. Spectators anchor the same arrangement on seat 0.
    final anchor = game.humanSeat >= 0 ? game.humanSeat : 0;
    final others = [
      for (var i = 1; i < game.seats.length; i++)
        (anchor + i) % game.seats.length,
    ];
    final positions = switch (others.length) {
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
            final seatWidth =
                ((constraints.maxHeight -
                            404 -
                            (game.isThousand ? 60 + 80 * scale : 0) -
                            144 * scale -
                            footer) /
                        2.36)
                    .clamp(
                      88.0,
                      ((constraints.maxWidth - 48) / 3).clamp(88.0, 144.0),
                    );
            final frameSize = Size(seatWidth, seatWidth * 1.18);
            final seatHeight = frameSize.height + 12 + 32 * scale;
            final handBottom = footer + 12;
            final ownBottom = handBottom + 144;
            final topSeat = 60 * scale + 44;
            final twoLowerSeats = game.seats.length >= 4;
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
                    bottom: positions[i].dy == 1 ? ownBottom : null,
                    width: seatWidth,
                    child: motion.seat(
                      others[i],
                      _seatPanel(game, l, others[i], frameSize),
                    ),
                  ),
                Positioned(
                  key: const ValueKey('table-center'),
                  top: topSeat + seatHeight + 16,
                  left: 12,
                  right: 12,
                  height: game.isThousand
                      ? 180 + 100 * scale
                      : 120 + 20 * scale,
                  child: _center(game, l, motion),
                ),
                if (!game.isMongol13 && !game.isDurak && !game.isThousand)
                  Positioned(
                    key: const ValueKey('table-stock'),
                    bottom:
                        ownBottom +
                        12 +
                        32 * scale +
                        (frameSize.height - 54) / 2,
                    left:
                        constraints.maxWidth * (twoLowerSeats ? .5 : .18) - 40,
                    child: Semantics(
                      label:
                          '${l('trump')} ${suitSymbols[game.trumpSuit]}, ${l('stock')}: ${game.stockCount}',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (game.trumpTaken)
                            Tooltip(
                              message: l('trumpTakenHint'),
                              child: Container(
                                key: const ValueKey('fixed-trump-suit'),
                                width: 36,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: const Color(0xff244b43),
                                  ),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        l('trump'),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xff244b43),
                                        ),
                                      ),
                                      Text(
                                        suitSymbols[game.trumpSuit],
                                        style: TextStyle(
                                          fontSize: 30,
                                          height: 1.1,
                                          color:
                                              game.trumpSuit == 1 ||
                                                  game.trumpSuit == 2
                                              ? const Color(0xffc62828)
                                              : const Color(0xff244b43),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else
                            CardView(game.trumpCard, width: 36),
                          const SizedBox(width: 8),
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
                            (game.seats.length == 6
                                ? .84
                                : twoLowerSeats
                                ? .78
                                : .5) -
                        seatWidth / 2,
                    bottom: ownBottom,
                    width: seatWidth,
                    child: motion.seat(
                      anchor,
                      _seatPanel(game, l, anchor, frameSize),
                    ),
                  ),
                if (!spectating && !replay)
                  Positioned(
                    key: const ValueKey('table-actions'),
                    right: 12,
                    left: 12,
                    bottom: 8,
                    child: IgnorePointer(
                      ignoring: motion.dealing,
                      child: _actions(game, l),
                    ),
                  ),
                if (game.autoPlaying)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 8,
                    child: _autoBanner(game, l),
                  ),
                Positioned(
                  key: const ValueKey('table-hand'),
                  left: 14,
                  right: 14,
                  bottom: handBottom,
                  height: 132,
                  child: _hand(game, motion),
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
                  '${l('round')} ${game.roundNo}',
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
          if (game is RemoteGameController && !game.spectating)
            IconButton(
              tooltip: l('chat'),
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => _showChatSheet(game, l),
            ),
          if (game is RemoteGameController && !game.spectating)
            const TableCallButton(),
        ],
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
    final s = game.seats[seat];
    final active =
        game.turn == seat &&
        game.phase != Phase.roundEnd &&
        game.phase != Phase.gameEnd;
    final name = game.isLocal ? _seatName(game, l, seat) : s.name;
    final bubble = game.chatBubbles[seat];
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    // Rule: players who passed sit this round out, dimmed, score unchanged.
    return Opacity(
      opacity: s.decision == Decision.pass || s.finished ? 0.45 : 1,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          if (s.wonCards.isNotEmpty)
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
              SizedBox(
                width: frameSize.width,
                height: frameSize.height,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: TurnCountdownAvatar(
                        name: s.name,
                        frameSize: frameSize,
                        avatar: CallAvatar(
                          name: s.name,
                          uid: game is RemoteGameController && !s.bot
                              ? s.rtcUid
                              : null,
                          portrait: true,
                          size: Size(frameSize.width - 8, frameSize.height - 8),
                        ),
                        active:
                            game is! ReplayController &&
                            active &&
                            (seat != game.humanSeat || game.humanTurn),
                        deadline: game.turnDeadline,
                        turnLabel: l('yourTurn'),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 10,
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
                    if (!game.isMongol13 &&
                        !game.isDurak &&
                        seat == game.dealer)
                      const Positioned(
                        left: 10,
                        top: 10,
                        child: CircleAvatar(
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
              const SizedBox(height: 12),
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
    final palette = context.watch<Palette>();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: palette.redPen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l('autoOn')),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => game.setAuto(false),
            child: Text(l('autoOff')),
          ),
        ],
      ),
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
                    padding: const EdgeInsets.fromLTRB(0, 12, 6, 12),
                    child: motion.handCard(
                      c,
                      CardView(
                        c,
                        width: 64,
                        selected: _selected.contains(c),
                        disabled: game.playPending,
                        onTap: motion.dealing
                            ? null
                            : () => _onCardTap(
                                game,
                                c,
                                playing: playing,
                                exchanging: exchanging,
                              ),
                      ),
                    ),
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
                    child: motion.handCard(
                      hand[i],
                      CardView(
                        hand[i],
                        width: width,
                        selected: _selected.contains(hand[i]),
                        disabled:
                            game.playPending ||
                            (playing && !legal.contains(hand[i])),
                        onTap: motion.dealing
                            ? null
                            : () => _onCardTap(
                                game,
                                hand[i],
                                playing: playing,
                                exchanging: exchanging,
                              ),
                      ),
                    ),
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
    final audio = context.read<AudioController>();
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
      audio.playSfx(SfxType.huhsh);
      setState(_selected.clear);
      game.play(rules.cardString(card));
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
        game.thousandAction(
          'play',
          value: rules.cardString(chosen),
          announce: announce,
        );
        setState(_selected.clear);
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
                  ? () => send(defending ? 'defend' : 'attack')
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
              ? () {
                  audio.playSfx(SfxType.huhsh);
                  game.playCombo(_selected.toList());
                  setState(_selected.clear);
                }
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
        return _tableButton(
          onPressed: () {
            audio.playSfx(SfxType.buttonTap);
            game.exchange(_selected.map(rules.cardString).toList());
            setState(_selected.clear);
          },
          child: Text(
            _selected.isEmpty
                ? l('keepAll')
                : '${l('exchangeN')} ${_selected.length}',
          ),
        );
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
        return const SizedBox.shrink();
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

  void _showChatSheet(GameController game, L l) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (var i = 0; i < l.phrases.length; i++)
              Padding(
                padding: const EdgeInsets.all(6),
                child: ActionChip(
                  label: Text(l.phrases[i]),
                  onPressed: () {
                    game.sendChat(i);
                    Navigator.pop(context);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

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
