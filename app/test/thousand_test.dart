import 'package:card/rules/card.dart';
import 'package:card/rules/rules.dart' show TrickCard;
import 'package:card/rules/thousand.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Thousand ten beats king, card points total 120', () {
    expect(
      thousandStrength(parseCard('TC')),
      greaterThan(thousandStrength(parseCard('KC'))),
    );
    expect(
      [
        for (var s = 0; s < 4; s++)
          for (var r = 9; r <= 14; r++) thousandPoints(s * 16 + r),
      ].fold(0, (int a, b) => a + b),
      120,
    );
  });
  test('KQ bid limits use suit bonuses and require both cards', () {
    final hand = ['KH', 'QH', 'KS', 'QS', 'QC'].map(parseCard).toList();
    expect(thousandMarriages(hand), [2, 3]);
    expect(thousandBidCap(hand), 260);
    expect(thousandBidCap([parseCard('AH')]), 120);
  });
  test('Follow suit has priority, void must trump, no mandatory overtake', () {
    final trick = [TrickCard(1, parseCard('AC'))];
    expect(
      thousandLegalCards(['9C', 'KH', 'AS'].map(parseCard).toList(), trick, 2),
      [parseCard('9C')],
    );
    expect(thousandLegalCards(['KH', 'AS'].map(parseCard).toList(), trick, 2), [
      parseCard('KH'),
    ]);
    expect(
      thousandLegalCards(
        ['KH', 'AS'].map(parseCard).toList(),
        trick,
        -1,
      ).length,
      2,
    );
  });
  test('Declaration requires previous trick win, lead, and held KQ', () {
    final hand = ['KH', 'QH', 'AC'].map(parseCard).toList();
    final k = parseCard('KH');
    expect(thousandCanAnnounce(hand, [], 1, k), isTrue);
    expect(thousandCanAnnounce(hand, [], 0, k), isFalse);
    expect(
      thousandCanAnnounce(hand, [TrickCard(2, parseCard('9H'))], 1, k),
      isFalse,
    );
    expect(thousandCanAnnounce([k], [], 1, k), isFalse);
    expect(thousandCanAnnounce(hand, [], 1, parseCard('AC')), isFalse);
  });
}
