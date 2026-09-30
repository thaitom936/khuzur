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
    // cards6_pkw.plist: 124 x 180 frames, eight columns. Suits are
    // diamonds, clubs, hearts, spades; each runs from 2 through ace.
    final atlasSuit = const [1, 0, 2, 3][rules.suitOf(card)];
    final index = atlasSuit * 13 + rules.rankOf(card) - 2;
    return Semantics(
      label: '${rankLabel(card)}${suitSymbols[rules.suitOf(card)]}',
      button: onTap != null,
      enabled: !disabled,
      child: GestureDetector(
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(width * .08),
            child: Opacity(
              opacity: disabled ? .4 : 1,
              child: LayoutBuilder(
                builder: (context, constraints) => OverflowBox(
                  alignment: Alignment(
                    -1 + (index % 8) * 2 / 7,
                    -1 + (index ~/ 8) * 2 / 6,
                  ),
                  minWidth: constraints.maxWidth * 8,
                  maxWidth: constraints.maxWidth * 8,
                  minHeight: constraints.maxHeight * 7,
                  maxHeight: constraints.maxHeight * 7,
                  child: Image.asset(
                    'assets/images/cards6_pkw.png',
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
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
      child: Center(
        child: Icon(
          Icons.diamond_outlined,
          size: width * 0.55,
          color: palette.trueWhite.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}
