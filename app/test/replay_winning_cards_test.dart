import 'package:card/game/replay_controller.dart';
import 'package:card/rules/card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'replay preserves the original face-up card across dealer trade and seeking',
    () {
      final replay = ReplayController({
        'config': {'decidePhase': false, 'exchangePhase': false},
        'rounds': [
          {
            'dealer': 0,
            'hands': [
              ['7C', '8C', '9C', 'TC', 'JC'],
              ['7D', '8D', '9D', 'TD', 'JD'],
            ],
            'trump': 'AS',
            'stock': <String>[],
            'scores': [15, 15],
            'actions': [
              {'s': 0, 'c': 'k', 'v': '7C'},
            ],
          },
        ],
      });
      addTearDown(replay.dispose);
      replay.stepForward();
      expect(replay.desyncError, isNull);
      expect(cardString(replay.trumpCard), '7C');
      expect(cardString(replay.trumpIndicatorCard), 'AS');
      replay.stepBack();
      expect(cardString(replay.trumpIndicatorCard), 'AS');
      expect(cardString(replay.trumpCard), 'AS');
    },
  );
  test('replay rebuilds winning cards when seeking backwards', () {
    final replay = ReplayController({
      'config': {'dealerTakesTrump': false},
      'rounds': [
        {
          'dealer': 0,
          'hands': [
            ['AC', 'KC', 'QC', 'JC', 'TC'],
            ['9C', '8C', '7C', 'AD', 'KD'],
          ],
          'trump': '7H',
          'stock': <String>[],
          'scores': [15, 15],
          'actions': <Map<String, dynamic>>[
            {'s': 1, 'c': 'd', 'v': true},
            {'s': 0, 'c': 'd', 'v': true},
            {'s': 1, 'c': 'e', 'v': <String>[]},
            {'s': 0, 'c': 'e', 'v': <String>[]},
            {'s': 1, 'c': 'p', 'v': 'AD'},
            {'s': 0, 'c': 'p', 'v': 'TC'},
            {'s': 1, 'c': 'p', 'v': 'KD'},
            {'s': 0, 'c': 'p', 'v': 'JC'},
          ],
        },
      ],
    });
    addTearDown(replay.dispose);
    for (var i = 0; i < 8; i++) {
      replay.stepForward();
    }
    expect(replay.desyncError, isNull);
    expect(replay.seats[1].wonCards, [parseCard('AD'), parseCard('KD')]);
    replay.stepBack();
    expect(replay.seats[1].wonCards, [parseCard('AD')]);
    replay.stepForward();
    expect(replay.seats[1].wonCards, [parseCard('AD'), parseCard('KD')]);
    expect(replay.seats[0].wonCards, isEmpty);
  });
}
