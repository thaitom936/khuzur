/// Runs the shared rule cases in `testdata/rules/` (repo root) against the
/// Dart engine. The same files are run against the Lua engine by
/// `server/test/run_rules.lua`, keeping both implementations in sync.
library;

import 'dart:convert';
import 'dart:io';

import 'package:card/rules/card.dart';
import 'package:card/rules/rules.dart';
import 'package:test/test.dart';

Directory _caseDir() {
  for (final path in ['../testdata/rules', 'testdata/rules']) {
    final dir = Directory(path);
    if (dir.existsSync()) return dir;
  }
  throw StateError('testdata/rules not found; run tests from the app directory');
}

void main() {
  final files = _caseDir()
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) throw StateError('no case files in testdata/rules');

  for (final file in files) {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    test(json['name'] as String? ?? file.path, () => _runCase(json));
  }
}

List<String> _strings(dynamic list) =>
    (list as List).cast<String>();

/// Sorts card strings by card value, matching the engine's output order.
List<String> _sortedCards(List<String> cards) =>
    [...cards]..sort((a, b) => parseCard(a).compareTo(parseCard(b)));

void _runCase(Map<String, dynamic> c) {
  final state = GameState.newRound(
    hands: [for (final h in c['hands'] as List) _strings(h)],
    trump: c['trump'] as String,
    stock: _strings(c['stock'] ?? []),
    dealer: c['dealer'] as int,
    config: RuleConfig.fromJson(
        (c['config'] as Map<String, dynamic>?) ?? const {}),
    scores: (c['scores'] as List?)?.cast<int>(),
  );

  var stepNo = 0;
  for (final stepAny in c['steps'] as List) {
    stepNo++;
    final step = stepAny as Map<String, dynamic>;
    final where = 'step $stepNo';

    if (step.containsKey('expect')) {
      _checkExpect(state, step['expect'] as Map<String, dynamic>, where);
    } else if (step.containsKey('legal')) {
      final legal = step['legal'] as Map<String, dynamic>;
      final got = state.legalCards(legal['seat'] as int).map(cardString);
      expect(got, _sortedCards(_strings(legal['cards'])), reason: '$where legal');
    } else {
      String? err;
      if (step.containsKey('decide')) {
        final a = step['decide'] as Map<String, dynamic>;
        err = state.decide(a['seat'] as int, a['play'] as bool);
      } else if (step.containsKey('exchange')) {
        final a = step['exchange'] as Map<String, dynamic>;
        err = state.exchange(a['seat'] as int, _strings(a['cards']));
      } else if (step.containsKey('play')) {
        final a = step['play'] as Map<String, dynamic>;
        err = state.play(a['seat'] as int, a['card'] as String);
      } else {
        fail('$where: unknown step');
      }
      expect(err, step['error'], reason: where);
    }
  }
}

const _phaseNames = {
  Phase.deciding: 'deciding',
  Phase.exchanging: 'exchanging',
  Phase.playing: 'playing',
  Phase.roundEnd: 'round_end',
  Phase.gameEnd: 'game_end',
};

void _checkExpect(GameState state, Map<String, dynamic> exp, String where) {
  if (exp.containsKey('phase')) {
    expect(_phaseNames[state.phase], exp['phase'], reason: '$where phase');
  }
  if (exp.containsKey('turn')) {
    expect(state.turn, exp['turn'], reason: '$where turn');
  }
  if (exp.containsKey('trickNo')) {
    expect(state.trickNo, exp['trickNo'], reason: '$where trickNo');
  }
  if (exp.containsKey('tricks')) {
    expect([for (final p in state.players) p.tricks], exp['tricks'],
        reason: '$where tricks');
  }
  if (exp.containsKey('scores')) {
    expect([for (final p in state.players) p.score], exp['scores'],
        reason: '$where scores');
  }
  if (exp.containsKey('winners')) {
    expect(state.winners, exp['winners'], reason: '$where winners');
  }
  if (exp.containsKey('hand')) {
    final hand = exp['hand'] as Map<String, dynamic>;
    final got =
        ([...state.players[hand['seat'] as int].hand]..sort()).map(cardString);
    expect(got, _sortedCards(_strings(hand['cards'])), reason: '$where hand');
  }
}
