import 'package:flutter/material.dart';

import '../style/player_avatar.dart';

/// The active player's turn cue. Timing follows the server deadline; this widget
/// never submits an action or creates a timeout for untimed practice games.
class TurnCountdownAvatar extends StatefulWidget {
  final String name;
  final bool active;
  final DateTime? deadline;
  final String turnLabel;

  const TurnCountdownAvatar({
    required this.name,
    required this.active,
    required this.deadline,
    required this.turnLabel,
    super.key,
  });

  @override
  State<TurnCountdownAvatar> createState() => _TurnCountdownAvatarState();
}

class _TurnCountdownAvatarState extends State<TurnCountdownAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;
  Duration _window = Duration.zero;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      animationBehavior: AnimationBehavior.preserve,
    );
    _sync(newDeadline: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced != _reduced) {
      _reduced = reduced;
      _sync();
    }
  }

  @override
  void didUpdateWidget(TurnCountdownAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.deadline != widget.deadline;
    if (changed || oldWidget.active != widget.active) {
      _sync(newDeadline: changed);
    }
  }

  void _sync({bool newDeadline = false}) {
    _clock.stop();
    final remaining = widget.deadline?.difference(DateTime.now());
    if (newDeadline) _window = remaining ?? Duration.zero;
    if (!widget.active) return;
    if (remaining != null) {
      if (remaining <= Duration.zero || _window <= Duration.zero) {
        _clock.value = 0;
        return;
      }
      _clock.duration = _window;
      _clock.reverse(
        from: (remaining.inMicroseconds / _window.inMicroseconds).clamp(0, 1),
      );
    } else if (!_reduced) {
      // Rotate on entry for untimed practice without inventing a deadline.
      _clock.duration = const Duration(milliseconds: 1800);
      _clock.forward(from: 0);
    } else {
      _clock.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _clock,
    child: PlayerAvatar(name: widget.name, size: 46),
    builder: (context, child) {
      final timed = widget.deadline != null;
      final seconds = (_window.inMilliseconds * _clock.value / 1000)
          .ceil()
          .clamp(0, 999);
      final urgent = timed && seconds <= (_window.inSeconds >= 8 ? 5 : 1);
      final color = urgent ? const Color(0xffff665d) : const Color(0xffd5fff6);
      return Semantics(
        label: widget.active ? widget.turnLabel : null,
        value: widget.active && timed ? '${seconds}s' : null,
        child: SizedBox(
          width: 58,
          height: 62,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              if (widget.active)
                Positioned(
                  top: 0,
                  child: SizedBox(
                    width: 58,
                    height: 58,
                    child: Transform.rotate(
                      angle: !timed && !_reduced ? _clock.value * 12.566 : 0,
                      child: CircularProgressIndicator(
                        key: const ValueKey('own-turn-progress'),
                        value: timed ? _clock.value : .75,
                        strokeWidth: 3,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.white24,
                        color: color,
                      ),
                    ),
                  ),
                ),
              Padding(padding: const EdgeInsets.all(6), child: child),
              if (widget.active && timed)
                Positioned(
                  bottom: 0,
                  child: Container(
                    key: const ValueKey('own-turn-seconds'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${seconds}s',
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        fontSize: 10,
                        height: 1.2,
                        color: Color(0xff183f35),
                        fontWeight: FontWeight.w700,
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

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }
}
