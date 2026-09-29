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
import 'card_widget.dart';

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

    if (game.phase != _lastPhase) {
      _lastPhase = game.phase;
      _selected.clear();
    }

    final isReplay = game is ReplayController;
    final spectating = game is RemoteGameController && game.spectating;

    return Scaffold(
      backgroundColor: palette.backgroundPlaySession,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _topBar(game, l),
                if (spectating)
                  Text(l('spectating'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _opponents(game, l),
                Expanded(child: _center(game, l)),
                if (game.autoPlaying) _autoBanner(game, l),
                _seatPanelRow(game, l),
                _hand(game),
                SizedBox(
                  height: 96,
                  child: Center(
                    child: isReplay
                        ? _replayControls(game)
                        : _actions(game, l),
                  ),
                ),
              ],
            ),
            if (!isReplay && game.phase == Phase.roundEnd)
              _roundEndOverlay(game, l),
            if (!isReplay && !spectating && game.phase == Phase.gameEnd)
              _gameEndOverlay(game, l),
          ],
        ),
      ),
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
            child: Text('⚠ ${game.desyncError}',
                style: const TextStyle(color: Colors.red, fontSize: 11)),
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

  Widget _topBar(GameController game, L l) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _leave(game),
          ),
          Text('${l('round')} ${game.roundNo}'),
          const Spacer(),
          Text('${l('trump')}: '),
          CardView(game.trumpCard, width: 30),
          const SizedBox(width: 12),
          Text('${l('stock')}: ${game.stockCount}'),
          const Spacer(),
          if (!game.isLocal)
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => _showChatSheet(game, l),
            ),
          InkResponse(
            onTap: () => GoRouter.of(context).push('/settings'),
            child: Image.asset('assets/images/settings.png',
                semanticLabel: 'Settings', width: 32),
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

  Widget _opponents(GameController game, L l) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var seat = 0; seat < game.seats.length; seat++)
          if (seat != game.humanSeat)
            _seatPanel(game, l, seat),
      ],
    );
  }

  Widget _seatPanelRow(GameController game, L l) {
    if (game.seats.isEmpty || game.humanSeat < 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _seatPanel(game, l, game.humanSeat),
    );
  }

  Widget _seatPanel(GameController game, L l, int seat) {
    final palette = context.watch<Palette>();
    final s = game.seats[seat];
    final active = game.turn == seat &&
        game.phase != Phase.roundEnd &&
        game.phase != Phase.gameEnd;
    final badge = switch (s.decision) {
      Decision.pass => ' · ${l('passed')}',
      Decision.play => ' · ${s.tricks}▲',
      Decision.none => '',
    };
    final bubble = game.chatBubbles[seat];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? palette.accept : palette.trueWhite,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.ink.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_seatName(game, l, seat)}'
                '${game.dealer == seat ? ' (D)' : ''}'
                '${s.online ? '' : ' · ${l('offline')}'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('${s.score}$badge'),
            ],
          ),
        ),
        if (bubble != null)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: palette.trueWhite,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              bubble < l.phrases.length ? l.phrases[bubble] : '…',
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }

  String _countdown(GameController game) {
    final deadline = game.turnDeadline;
    if (deadline == null) return '';
    final left = deadline.difference(DateTime.now()).inSeconds;
    return left > 0 ? ' ($left)' : '';
  }

  Widget _center(GameController game, L l) {
    final trick = game.completedTrick ?? game.trick;
    final String status;
    if (game.completedTrickWinner != null) {
      status = l.fmt('takesTrick', _seatName(game, l, game.completedTrickWinner!));
    } else if (game.humanTurn) {
      status = switch (game.phase) {
        Phase.deciding => l('decideHint'),
        Phase.exchanging => l.fmt('exchangeHint', game.maxExchangeNow),
        Phase.playing => l('yourTurn') + _countdown(game),
        _ => '',
      };
    } else if (game.turn >= 0 &&
        game.turn < game.seats.length &&
        (game.phase == Phase.deciding ||
            game.phase == Phase.exchanging ||
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
          height: 100,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final t in trick)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _Appear(
                    key: ValueKey('t${t.seat}-${t.card}'),
                    child: Column(
                      children: [
                        Text(_seatName(game, l, t.seat),
                            style: const TextStyle(fontSize: 11)),
                        CardView(t.card, width: 44),
                      ],
                    ),
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

  Widget _hand(GameController game) {
    final hand = [...game.hand]..sort();
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
              child: _Appear(
                key: ValueKey('h$card-${game.roundNo}'),
                child: CardView(
                  card,
                  selected: _selected.contains(card),
                  disabled: playing && !legal.contains(card),
                  onTap: () => _onCardTap(game, card,
                      playing: playing, exchanging: exchanging),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onCardTap(GameController game, int card,
      {required bool playing, required bool exchanging}) {
    final audio = context.read<AudioController>();
    if (playing) {
      if (_selected.contains(card)) {
        audio.playSfx(SfxType.huhsh);
        setState(_selected.clear);
        game.play(rules.cardString(card));
      } else {
        setState(() => _selected
          ..clear()
          ..add(card));
      }
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
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MyButton(
              onPressed: () {
                audio.playSfx(SfxType.buttonTap);
                game.decide(true);
              },
              child: Text(l('playBtn')),
            ),
            const SizedBox(width: 16),
            MyButton(
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
        return MyButton(
          onPressed: () {
            audio.playSfx(SfxType.buttonTap);
            game.exchange(_selected.map(rules.cardString).toList());
            setState(_selected.clear);
          },
          child: Text(_selected.isEmpty
              ? l('keepAll')
              : '${l('exchangeN')} ${_selected.length}'),
        );
      case Phase.playing:
        return Text(l('playHint'));
      default:
        return const SizedBox.shrink();
    }
  }

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
                  child: Text('${l('score')} ${game.seats[seat].score}',
                      textAlign: TextAlign.right),
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
      Text(l.fmt('roundFinished', game.roundNo),
          style: Theme.of(context).textTheme.titleLarge),
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
          Text(humanWon ? l('youWin') : l('gameOver'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
              '${l('winner')}: ${winners.map((s) => _seatName(game, l, s)).join(', ')}'),
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
          MyButton(
            onPressed: () => _leave(game),
            child: Text(l('backToMenu')),
          ),
        ]),
        if (humanWon)
          Positioned.fill(
            child: IgnorePointer(child: Confetti(isStopped: false)),
          ),
      ],
    );
  }
}

/// Pop-in animation for newly appearing cards (deals and plays).
class _Appear extends StatelessWidget {
  final Widget child;

  const _Appear({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      child: child,
      builder: (context, v, child) => Transform.translate(
        offset: Offset(0, 14 * (1 - v)),
        child: Transform.scale(
          scale: 0.8 + 0.2 * v,
          child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
        ),
      ),
    );
  }
}
