import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../rules/card.dart' as rules;
import '../style/palette.dart';

const suitSymbols = ['♣', '♦', '♥', '♠'];

String rankLabel(int card) {
  final rank = rules.rankOf(card);
  return rank == 10 ? '10' : rules.rankChars[rank]!;
}

/// One playing card. [width] scales the whole card (height is 1.5x).
class CardView extends StatelessWidget {
  final int card;
  final double width;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const CardView(
    this.card, {
    this.width = 64,
    this.selected = false,
    this.disabled = false,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();
    final suit = rules.suitOf(card);
    final red = suit == 1 || suit == 2; // diamonds, hearts
    final color = disabled
        ? palette.ink.withValues(alpha: 0.35)
        : (red ? palette.redPen : palette.ink);

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: width,
        height: width * 1.5,
        transform: Matrix4.translationValues(0, selected ? -12 : 0, 0),
        decoration: BoxDecoration(
          color: disabled
              ? palette.trueWhite.withValues(alpha: 0.7)
              : palette.trueWhite,
          border: Border.all(
            color: selected ? palette.redPen : palette.ink,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(width * 0.1),
          boxShadow: selected
              ? [const BoxShadow(blurRadius: 6, color: Colors.black26)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              rankLabel(card),
              style: TextStyle(
                color: color,
                fontSize: width * 0.34,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
            Text(
              suitSymbols[suit],
              style: TextStyle(color: color, fontSize: width * 0.4, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}

/// A face-down card back.
class CardBack extends StatelessWidget {
  final double width;

  const CardBack({this.width = 64, super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();
    return Container(
      width: width,
      height: width * 1.5,
      decoration: BoxDecoration(
        color: palette.darkPen,
        border: Border.all(color: palette.ink),
        borderRadius: BorderRadius.circular(width * 0.1),
      ),
    );
  }
}
