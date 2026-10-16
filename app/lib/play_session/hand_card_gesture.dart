import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A deliberate upward drag is an alternative to the table's play button.
/// Keep the motion anchor inside the transform so flights start at the release.
class HandCardGesture extends StatefulWidget {
  const HandCardGesture({required this.child, this.onPlay, super.key});

  static const playDistance = 72.0;
  final Widget child;
  final VoidCallback? onPlay;

  @override
  State<HandCardGesture> createState() => _HandCardGestureState();
}

class _HandCardGestureState extends State<HandCardGesture> {
  double _startY = 0;
  double _offset = 0;
  bool _released = false;

  @override
  void didUpdateWidget(HandCardGesture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPlay == null) _offset = 0;
  }

  void _reset() => setState(() => _offset = 0);

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _released = false,
    onPointerUp: (_) => _released = true,
    onPointerCancel: (_) {
      _released = false;
      _reset();
    },
    child: GestureDetector(
      dragStartBehavior: DragStartBehavior.down,
      onVerticalDragStart: widget.onPlay == null
          ? null
          : (details) => _startY = details.globalPosition.dy,
      onVerticalDragUpdate: widget.onPlay == null
          ? null
          : (details) => setState(() {
              _offset = (details.globalPosition.dy - _startY).clamp(
                -180.0,
                0.0,
              );
            }),
      onVerticalDragCancel: widget.onPlay == null ? null : _reset,
      onVerticalDragEnd: widget.onPlay == null
          ? null
          : (_) {
              if (_released && _offset <= -HandCardGesture.playDistance) {
                widget.onPlay?.call();
              }
              if (mounted) _reset();
            },
      child: Transform.translate(
        offset: Offset(0, _offset),
        child: widget.child,
      ),
    ),
  );
}
