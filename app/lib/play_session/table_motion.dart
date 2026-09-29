import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game/game_controller.dart';
import '../rules/rules.dart';
import 'card_widget.dart';

/// One coordinate space for the table and its flights, including when the
/// compact viewport scrolls or the hand is scaled to fit the screen.
class CardTableMotion extends StatefulWidget {
  final GameController game;
  final Widget Function(BuildContext, CardTableMotionState) builder;

  const CardTableMotion({required this.game, required this.builder, super.key});

  @override
  State<CardTableMotion> createState() => CardTableMotionState();
}

class CardTableMotionState extends State<CardTableMotion>
    with SingleTickerProviderStateMixin {
  final _root = GlobalKey();
  final _deck = GlobalKey();
  final _hands = <int, GlobalKey>{};
  final _seats = <int, GlobalKey>{};
  final _tricks = <int, GlobalKey>{};
  final _hiddenHand = <int>{};
  final _hiddenTrick = <int>{};
  final _flights = <_Flight>[];
  final _cardVersions = <int, int>{};
  final _frame = ValueNotifier<double>(0);
  late final Ticker _ticker;
  TableMotionEvent? _seen;
  int _generation = 0;
  double _elapsed = 0;
  bool _reduceMotion = false;

  bool get dealing =>
      _hiddenHand.isNotEmpty ||
      _flights.any((f) => f.kind == TableMotionKind.deal);
  bool get animating =>
      _flights.isNotEmpty || _hiddenHand.isNotEmpty || _hiddenTrick.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    widget.game.addListener(_onGame);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _clear();
    if (_seen == null && widget.game.tableMotion != null) {
      _seen = widget.game.tableMotion;
      // A fresh deal may precede navigation by a frame. Existing table snapshots
      // and old plays are displayed immediately when entering/reconnecting.
      if (!_reduceMotion &&
          _seen!.kind == TableMotionKind.deal &&
          widget.game.phase == Phase.deciding) {
        _deal();
      }
    }
  }

  @override
  void didUpdateWidget(CardTableMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game != widget.game) {
      oldWidget.game.removeListener(_onGame);
      widget.game.addListener(_onGame);
      _seen = widget.game.tableMotion;
      _clear();
    }
  }

  void _clear() {
    _generation++;
    _ticker.stop();
    _flights.clear();
    _hiddenHand.clear();
    _hiddenTrick.clear();
    _cardVersions.clear();
  }

  void _onGame() {
    final event = widget.game.tableMotion;
    if (identical(event, _seen)) return;
    _seen = event;
    if (event == null) return;
    setState(() {
      if (_reduceMotion || event.kind == TableMotionKind.reset) {
        _clear();
      } else if (event.kind == TableMotionKind.deal) {
        _clear();
        _deal();
      } else {
        _play(event.card!, returning: event.kind == TableMotionKind.returnCard);
      }
    });
  }

  Rect? _rect(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject();
    final root = _root.currentContext?.findRenderObject();
    if (box is! RenderBox || root is! RenderBox || !box.hasSize) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(root),
      Offset.zero & box.size,
    );
  }

  Rect? _seatRect(int seat) {
    final rect = _rect(_seats[seat]);
    return rect == null
        ? null
        : Rect.fromCenter(center: rect.center, width: 36, height: 54);
  }

  void _afterLayout(VoidCallback action) {
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) setState(action);
    });
  }

  void _add(_Flight flight) {
    if (!_ticker.isActive) {
      _elapsed = 0;
      _ticker.start();
    }
    flight.start += _elapsed;
    _flights.add(flight);
  }

  void _deal() {
    final game = widget.game;
    final hand = [...game.displayHand]..sort();
    final seatCount = game.seats.length;
    final dealer = game.dealer;
    final human = game.humanSeat;
    _hiddenHand.addAll(hand);
    _afterLayout(() {
      final from = _rect(_deck);
      if (from == null || seatCount == 0) {
        _hiddenHand.clear();
        return;
      }
      // Five rounds, clockwise from the dealer. Only our own cards are revealed.
      for (var n = 0; n < 5; n++) {
        for (var offset = 1; offset <= seatCount; offset++) {
          final seat = (dealer + offset) % seatCount;
          final card = seat == human && n < hand.length ? hand[n] : null;
          final to = card == null ? _seatRect(seat) : _rect(_hands[card]);
          if (to == null) {
            if (card != null) _hiddenHand.remove(card);
            continue;
          }
          _add(
            _Flight(
              from: from,
              to: to,
              card: card,
              kind: TableMotionKind.deal,
              start: (n * seatCount + offset - 1) * 32.0,
              duration: 320,
            ),
          );
        }
      }
    });
  }

  void _play(TrickCard card, {required bool returning}) {
    final version = (_cardVersions[card.card] ?? 0) + 1;
    _cardVersions[card.card] = version;
    Rect? from;
    // A fast rejection reverses the card from its current location, without
    // teleporting to the centre first.
    for (final flight in _flights.where((f) => f.card == card.card)) {
      from = flight.rectAt(_elapsed);
    }
    _flights.removeWhere((f) => f.card == card.card);
    _hiddenHand.remove(card.card);
    _hiddenTrick.remove(card.card);
    from ??= returning
        ? _rect(_tricks[card.card])
        : (card.seat == widget.game.humanSeat
              ? _rect(_hands[card.card])
              : null);
    from ??= _seatRect(card.seat) ?? _rect(_deck);
    final origin = from;
    final hidden = returning ? _hiddenHand : _hiddenTrick;
    hidden.add(card.card);
    _afterLayout(() {
      if (_cardVersions[card.card] != version) return;
      final to = _rect(returning ? _hands[card.card] : _tricks[card.card]);
      if (origin == null || to == null) {
        hidden.remove(card.card);
        return;
      }
      _add(
        _Flight(
          from: origin,
          to: to,
          card: card.card,
          kind: returning ? TableMotionKind.returnCard : TableMotionKind.play,
          start: 0,
          duration: returning ? 260 : 280,
        ),
      );
    });
  }

  void _tick(Duration elapsed) {
    _elapsed = elapsed.inMicroseconds / 1000;
    // Other cards arriving and viewport resizing can move a card's final slot.
    for (final flight in _flights) {
      final target = flight.kind == TableMotionKind.play
          ? _tricks[flight.card]
          : _hands[flight.card];
      flight.to = _rect(target) ?? flight.to;
    }
    final done = _flights.where((f) => f.progress(_elapsed) >= 1).toList();
    if (done.isNotEmpty) {
      setState(() {
        for (final flight in done) {
          _flights.remove(flight);
          if (flight.kind == TableMotionKind.play) {
            _hiddenTrick.remove(flight.card);
          } else {
            _hiddenHand.remove(flight.card);
          }
        }
      });
    }
    _frame.value = _elapsed;
    if (_flights.isEmpty) _ticker.stop();
  }

  Widget seat(int seat, Widget child) =>
      KeyedSubtree(key: _seats.putIfAbsent(seat, GlobalKey.new), child: child);

  Widget handCard(int card, Widget child) => KeyedSubtree(
    key: _hands.putIfAbsent(card, GlobalKey.new),
    child: IgnorePointer(
      ignoring: _hiddenHand.contains(card),
      child: Opacity(opacity: _hiddenHand.contains(card) ? 0 : 1, child: child),
    ),
  );

  Widget trickCard(int card, Widget child) => KeyedSubtree(
    key: _tricks.putIfAbsent(card, GlobalKey.new),
    child: Opacity(opacity: _hiddenTrick.contains(card) ? 0 : 1, child: child),
  );

  Widget deck({double width = 28, int? count}) => SizedBox(
    key: _deck,
    width: width + 3,
    height: width * 1.5 + 3,
    child: Stack(
      children: [
        Positioned(left: 3, top: 3, child: CardBack(width: width)),
        Positioned(left: 0, top: 0, child: CardBack(width: width)),
        if (count != null)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xff183f35),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$count',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Stack(
    key: _root,
    children: [
      widget.builder(context, this),
      Positioned.fill(
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _frame,
              builder: (context, _) => Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final flight in _flights)
                    if (_elapsed >= flight.start) _flightWidget(flight),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _flightWidget(_Flight flight) {
    final t = flight.progress(_elapsed);
    final rect = flight.rectAt(_elapsed);
    final dealing = flight.kind == TableMotionKind.deal;
    final flip = dealing ? ((t - 0.55) / 0.45).clamp(0.0, 1.0) : 1.0;
    final front = flight.card != null && flip >= 0.5;
    return Positioned.fromRect(
      rect: rect,
      child: Transform.rotate(
        angle: math.sin(t * math.pi) * -0.1,
        child: Transform.scale(
          scaleX: dealing && flight.card != null
              ? math.cos(flip * math.pi).abs().clamp(0.08, 1.0)
              : 1,
          child: DecoratedBox(
            key: ValueKey(
              'flying-${flight.kind.name}-${flight.card}-${flight.start}',
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: FittedBox(
              child: front ? CardView(flight.card!) : const CardBack(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.game.removeListener(_onGame);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }
}

class _Flight {
  final Rect from;
  Rect to;
  final int? card;
  final TableMotionKind kind;
  double start;
  final double duration;

  _Flight({
    required this.from,
    required this.to,
    required this.card,
    required this.kind,
    required this.start,
    required this.duration,
  });

  double progress(double elapsed) => ((elapsed - start) / duration).clamp(0, 1);

  Rect rectAt(double elapsed) {
    final t = progress(elapsed);
    final eased = Curves.easeOutCubic.transform(t);
    return Rect.lerp(
      from,
      to,
      eased,
    )!.shift(Offset(0, -24 * math.sin(t * math.pi)));
  }
}
