import 'dart:convert';
import 'dart:io';
import 'package:card/rules/card.dart';
import 'package:card/rules/durak.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases =
      jsonDecode(File('../testdata/durak/defence.json').readAsStringSync())
          as List;
  for (final c in cases) {
    test('Durak ${c['attack']} vs ${c['cover']} trump ${c['trump']}', () {
      expect(
        durakBeats(
          parseCard(c['attack'] as String),
          parseCard(c['cover'] as String),
          c['trump'] as int,
        ),
        c['beats'],
      );
    });
  }
  test('hints respect visible ranks, covering and transfer limits', () {
    final pairs = [DurakPair(parseCard('6C'), 0, parseCard('7C'), 1)];
    var hint = durakHint(
      [parseCard('7D'), parseCard('9D')],
      pairs,
      'add',
      2,
      5,
      false,
      6,
    );
    expect(hint.action, 'attack');
    expect(hint.cards, [parseCard('7D')]);
    hint = durakHint([parseCard('9D')], pairs, 'add', 2, 5, false, 6);
    expect(hint.action, 'finish');
    final open = [DurakPair(parseCard('6C'), 0)];
    hint = durakHint(
      [parseCard('7C'), parseCard('6H')],
      open,
      'defend',
      2,
      5,
      false,
      6,
    );
    expect(hint.action, 'defend');
    expect(hint.cards, [parseCard('7C')]);
    expect(hint.target, 0);
    hint = durakHint([parseCard('6D')], open, 'defend', 2, 1, true, 2, 5);
    expect(hint.action, 'transfer');
    hint = durakHint([parseCard('6D')], open, 'defend', 2, 5, true, 1, 5);
    expect(hint.action, 'take');
    hint = durakHint([parseCard('6D')], pairs, 'defend', 2, 5, true, 6, 5);
    expect(hint.action, 'take');
  });
}
