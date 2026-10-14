import 'dart:convert';
import 'dart:io';
import 'package:card/rules/card.dart';
import 'package:card/rules/mongol13.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> cards(List<dynamic> a) =>
    a.map((s) => parseCard(s as String)).toList();
void main() {
  final cases =
      jsonDecode(
            File('../testdata/mongol13/combinations.json').readAsStringSync(),
          )
          as List;
  for (var i = 0; i < cases.length; i++) {
    final c = cases[i] as Map;
    test('Mongol 13 shared combination $i', () {
      final combo = m13Combo(cards(c['cards'] as List));
      expect(combo?.kind, c['kind']);
      if (c['other'] != null) {
        expect(combo!.beats(m13Combo(cards(c['other'] as List))!), c['beats']);
      }
    });
  }
  test(
    'opening hint includes minimum; reply can pass; no duplicate or foreign cards',
    () {
      final hand = cards([
        '3D',
        '3C',
        '4S',
        '5H',
        '6C',
        '7D',
        '8S',
        '9D',
        'TD',
        'JS',
        'QS',
        'KH',
        'AD',
      ]);
      final first = m13Hint(hand, [], parseCard('3D'));
      expect(first, contains(parseCard('3D')));
      expect(m13CanPlay(hand, first, [], parseCard('3D')), isTrue);
      expect(m13CanPlay(hand, cards(['AD']), [], parseCard('3D')), isFalse);
      expect(m13CanPlay(hand, cards(['2D']), [], null), isFalse);
      expect(m13Hint(hand, cards(['2S']), null), isEmpty);
      expect(m13CanPlay(hand, cards(['3D', '3D']), [], null), isFalse);
    },
  );
}
