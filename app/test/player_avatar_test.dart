import 'package:card/style/player_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default assignments are deterministic for Unicode and empty names', () {
    for (final name in ['', 'Bataa', 'Тэмүүлэн', '玩家一', '🐻 Tom']) {
      expect(defaultAvatarFor(' $name '), defaultAvatarFor(name));
    }
    expect(
      [
        'Bataa',
        'Oyuna',
        'Bold',
        'Anar',
        'Temuulen',
      ].map(defaultAvatarFor).toSet().length,
      greaterThan(2),
    );
  });

  testWidgets('all twelve avatars render at lobby and table sizes', (
    tester,
  ) async {
    for (final size in [36.0, 46.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Wrap(
              children: [
                for (final avatar in DefaultAvatar.values)
                  PlayerAvatar(name: avatar.name, avatar: avatar, size: size),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(PlayerAvatar), findsNWidgets(12));
      expect(tester.takeException(), isNull);
    }
  });
}
