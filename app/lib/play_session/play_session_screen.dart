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
import '../rules/card.dart' as rules;
import '../rules/rules.dart';
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
    return ChangeNotifierProvider<GameController>.value(
      value: context.read<RemoteGameController>(),
      child: const TableView(),
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

    if (game is RemoteGameController && game.spectating && !game.started) {
      return Scaffold(
        backgroundColor: palette.backgroundMain,
        appBar: AppBar(
          title: Text(l('waitingFriends')),
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
        bottomNavigationBar: SafeArea(child: SpectatorControls(game: game)),
      );
    }

    return Scaffold(
      backgroundColor: palette.backgroundPlaySession,
      body: SafeArea(
        child: _tableViewport(
          replay: isReplay,
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
                    !spectating &&
                    !motion.animating &&
                    game.phase == Phase.gameEnd)
                  _gameEndOverlay(game, l),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tableViewport({required bool replay, required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep cards and actions readable in short windows instead of letting
        // the centre overflow into the player's hand when they sit down.
        final minimumHeight =
            (replay ? 920.0 : 820.0) *
            MediaQuery.textScalerOf(context).scale(1).clamp(1, 2);
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
      } else if (game.started && !game.gameOver) {
        game.suspended = true; // stay seated; auto-play covers the turns
      } else {
        game.leaveRoom();
      }
      GoRouter.of(context).go('/online');
    } else if (game is ReplayController) {
      GoRouter.of(context).go('/online');
    } else {
      GoRouter.of(context).go('/');
    }
  }

  Widget _tableLayout(GameController game, L l, CardTableMotionState motion) {
    final spectating = game is RemoteGameController && game.spectating;
    final replay = game is ReplayController;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    // Rotate the table around the viewer. Spectators use seat zero as the
    // bottom anchor, preserving every player's physical position when seated.
    final anchor = game.humanSeat >= 0 ? game.humanSeat : 0;
    final others = [
      for (var i = 1; i < game.seats.length; i++)
        (anchor + i) % game.seats.length,
    ];
    final positions = switch (others.length) {
      1 => const [Offset(.5, 0)],
      2 => const [Offset(.75, 0), Offset(.25, 0)],
      3 => const [Offset(.87, 1), Offset(.5, 0), Offset(.13, 1)],
      _ => const [
        Offset(.87, 1),
        Offset(.75, 0),
        Offset(.25, 0),
        Offset(.13, 1),
      ],
    };
    return DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.white),
      child: IconTheme(
        data: const IconThemeData(color: Colors.white),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final seatWidth = (constraints.maxWidth * .26).clamp(80.0, 124.0);
            final handBottom = spectating || replay ? 74.0 * scale : 18.0;
            final ownBottom = (spectating ? 18.0 : handBottom) + 108.0 * scale;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(top: 0, left: 0, right: 0, child: _topBar(game, l)),
                for (var i = 0; i < others.length; i++)
                  Positioned(
                    key: ValueKey('table-seat-${others[i]}'),
                    left:
                        constraints.maxWidth * positions[i].dx - seatWidth / 2,
                    top: positions[i].dy == 0 ? 76 * scale : null,
                    bottom: positions[i].dy == 1
                        ? ownBottom + 122 * scale
                        : null,
                    width: seatWidth,
                    child: motion.seat(
                      others[i],
                      _seatPanel(game, l, others[i]),
                    ),
                  ),
                Positioned(
                  top: constraints.maxHeight * .28,
                  left: 12,
                  right: 12,
                  height: 150 * scale,
                  child: _center(game, l, motion),
                ),
                Positioned(
                  key: const ValueKey('table-stock'),
                  top: constraints.maxHeight * .49,
                  left: 12,
                  child: Semantics(
                    label: '${l('trump')}, ${l('stock')}: ${game.stockCount}',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CardView(game.trumpCard, width: 40),
                        const SizedBox(width: 8),
                        motion.deck(width: 40, count: game.stockCount),
                      ],
                    ),
                  ),
                ),
                if (game.seats.isNotEmpty)
                  Positioned(
                    key: ValueKey('table-seat-$anchor'),
                    left: (constraints.maxWidth - seatWidth) / 2,
                    bottom: ownBottom,
                    width: seatWidth,
                    child: motion.seat(anchor, _seatPanel(game, l, anchor)),
                  ),
                if (!game.isLocal && !spectating && !replay)
                  Positioned(
                    left: 16,
                    bottom: ownBottom + 12,
                    child: IconButton.filled(
                      tooltip: l('chat'),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: context
                            .read<Palette>()
                            .backgroundPlaySession,
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      onPressed: () => _showChatSheet(game, l),
                    ),
                  ),
                if (!spectating && !replay)
                  Positioned(
                    key: const ValueKey('table-actions'),
                    right: 12,
                    bottom: ownBottom,
                    width: seatWidth,
                    child: IgnorePointer(
                      ignoring: motion.dealing,
                      child: _actions(game, l),
                    ),
                  ),
                if (game.autoPlaying)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: ownBottom + 230 * scale,
                    child: _autoBanner(game, l),
                  ),
                Positioned(
                  key: const ValueKey('table-hand'),
                  left: 14,
                  right: 14,
                  bottom: handBottom,
                  height: 96,
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
                      : '${l('tableLabel')} ${game.roomCode}',
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

  Widget _seatPanel(GameController game, L l, int seat) {
    final s = game.seats[seat];
    final active =
        game.turn == seat &&
        game.phase != Phase.roundEnd &&
        game.phase != Phase.gameEnd;
    final name = game.isLocal ? _seatName(game, l, seat) : s.name;
    final bubble = game.chatBubbles[seat];
    // Rule: players who passed sit this round out, dimmed, score unchanged.
    return Opacity(
      opacity: s.decision == Decision.pass ? 0.45 : 1,
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 76,
          height: 62,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: seat == game.humanSeat && game is! ReplayController
                    ? TurnCountdownAvatar(
                        name: s.name,
                        active: game.humanTurn,
                        deadline: game.turnDeadline,
                        turnLabel: l('yourTurn'),
                      )
                    : AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: active
                                ? const Color(0xffffd166)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: PlayerAvatar(name: s.name, size: 46),
                      ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
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
                    '${s.score}',
                    style: const TextStyle(
                      color: Color(0xff244b43),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              if (seat == game.dealer)
                const Positioned(
                  left: 0,
                  top: 1,
                  child: Text(
                    'D',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              // Won tricks pile up on the avatar (每墩累加显示).
              if (s.tricks > 0)
                Positioned(left: 0, bottom: 0, child: _trickPile(s.tricks)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
        ),
        Text(
          s.decision == Decision.pass
              ? l('passed')
              : !s.online && !s.bot
              ? l('offline')
              : ' ',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: Colors.white70),
        ),
        if (bubble != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              bubble < l.phrases.length ? l.phrases[bubble] : '…',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xff244b43)),
            ),
          ),
      ],
      ),
    );
  }

  /// Mini pile of card backs on the avatar showing tricks won so far.
  Widget _trickPile(int tricks) {
    final backs = tricks > 4 ? 4 : tricks;
    return SizedBox(
      width: 16 + 4.0 * (backs - 1) + 14,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var k = 0; k < backs; k++)
            Positioned(left: k * 4.0, top: 0, child: const CardBack(width: 14)),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: const Color(0xffffd166),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$tricks',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
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
    // Rule: centre cards are shown smallest to largest, without names.
    final trick = [...game.displayTrick]..sort((a, b) =>
        rules.rankOf(a.card) != rules.rankOf(b.card)
            ? rules.rankOf(a.card) - rules.rankOf(b.card)
            : a.card - b.card);
    final String status;
    if (game.completedTrickWinner != null) {
      status = l.fmt(
        'takesTrick',
        _seatName(game, l, game.completedTrickWinner!),
      );
    } else if (game.humanTurn) {
      status = switch (game.phase) {
        Phase.deciding => l('decideHint'),
        Phase.exchanging => l.fmt('exchangeHint', game.maxExchangeNow),
        Phase.swapping => l('swapHint'),
        Phase.playing => l('yourTurn') + _countdown(game),
        _ => '',
      };
    } else if (game.turn >= 0 &&
        game.turn < game.seats.length &&
        (game.phase == Phase.deciding ||
            game.phase == Phase.exchanging ||
            game.phase == Phase.swapping ||
            game.phase == Phase.playing)) {
      status =
          l.fmt('thinking', _seatName(game, l, game.turn)) + _countdown(game);
    } else {
      status = '';
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: 88,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final t in trick)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      motion.trickCard(t.card, CardView(t.card, width: 44)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(status, textAlign: TextAlign.center),
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
    final hand = [...game.displayHand]..sort();
    final playing = game.phase == Phase.playing && game.humanTurn;
    final exchanging = game.phase == Phase.exchanging && game.humanTurn;
    final legal = playing ? game.legalCards() : hand;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final card in hand)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: motion.handCard(
                card,
                CardView(
                  card,
                  selected: _selected.contains(card),
                  disabled:
                      game.playPending || (playing && !legal.contains(card)),
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
            ),
        ],
      ),
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
      audio.playSfx(SfxType.huhsh);
      setState(_selected.clear);
      game.play(rules.cardString(card));
    } else if (exchanging) {
      setState(() {
        if (!_selected.remove(card)) {
          if (_selected.length < game.maxExchangeNow) _selected.add(card);
        }
      });
    }
  }

  Widget _actions(GameController game, L l) {
    if (!game.humanTurn) return const SizedBox.shrink();
    final audio = context.read<AudioController>();

    switch (game.phase) {
      case Phase.deciding:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tableButton(
              onPressed: () {
                audio.playSfx(SfxType.buttonTap);
                game.decide(true);
              },
              child: Text(l('playBtn')),
            ),
            const SizedBox(height: 12),
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
          ],
        );
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
      case Phase.swapping:
        // Rule: after the exchanges, the trump-seven holder may trade it
        // for the face-up trump card.
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tableButton(
              onPressed: () {
                audio.playSfx(SfxType.buttonTap);
                game.swapTrump();
              },
              child: Text('${l('swapSeven')} '
                  '${rankLabel(game.trumpCard)}${suitSymbols[rules.suitOf(game.trumpCard)]}'),
            ),
            const SizedBox(height: 12),
            _tableButton(
              danger: true,
              onPressed: () {
                audio.playSfx(SfxType.buttonTap);
                game.skipSwap();
              },
              child: Text(l('keepSeven')),
            ),
          ],
        );
      case Phase.playing:
        return const SizedBox.shrink();
      default:
        return const SizedBox.shrink();
    }
  }

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
                    game.seats[seat].decision == Decision.pass
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
            humanWon ? l('youWin') : l('gameOver'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '${l('winner')}: ${winners.map((s) => _seatName(game, l, s)).join(', ')}',
          ),
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
