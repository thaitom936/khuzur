import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A compact playback indicator, rather than a decoded audio amplitude graph.
class ChatAudioWaveform extends StatefulWidget {
  const ChatAudioWaveform({super.key, required this.playing});

  final bool playing;

  @override
  State<ChatAudioWaveform> createState() => _ChatAudioWaveformState();
}

class _ChatAudioWaveformState extends State<ChatAudioWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 840),
  );

  void syncAnimation() {
    if (widget.playing &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled) {
      if (!animation.isAnimating) animation.repeat();
    } else {
      animation.stop();
      animation.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncAnimation();
  }

  @override
  void didUpdateWidget(ChatAudioWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncAnimation();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 40,
      height: 18,
      child: CustomPaint(
        painter: _PlaybackWavePainter(
          animation,
          color: Theme.of(context).colorScheme.primary,
          playing: widget.playing,
        ),
      ),
    ),
  );

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }
}

class _PlaybackWavePainter extends CustomPainter {
  _PlaybackWavePainter(
    this.animation, {
    required this.color,
    required this.playing,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final bool playing;
  static const levels = [.28, .58, .85, .46, 1.0, .65, .36, .72];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final step = size.width / levels.length;
    for (var i = 0; i < levels.length; i++) {
      final movement = playing
          ? .35 +
                .65 *
                    (.5 + .5 * math.sin(animation.value * math.pi * 2 + i * .9))
          : 1.0;
      final height = (size.height * levels[i] * movement).clamp(
        3.0,
        size.height,
      );
      final x = step * (i + .5);
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PlaybackWavePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.playing != playing;
}
