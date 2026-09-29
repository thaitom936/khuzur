import 'package:card/play_session/turn_countdown_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(
    WidgetTester tester, {
    required DateTime? deadline,
    bool active = true,
    bool reduced = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Center(
            child: TurnCountdownAvatar(
              name: 'Bataa',
              active: active,
              deadline: deadline,
              turnLabel: 'Your turn',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'own turn ring drains smoothly, counts seconds and warns at five',
    (tester) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      await show(tester, deadline: deadline);
      CircularProgressIndicator ring() =>
          tester.widget(find.byKey(const ValueKey('own-turn-progress')));
      expect(ring().value, closeTo(1, .02));
      await tester.pump(const Duration(seconds: 6));
      expect(ring().value, closeTo(.4, .03));
      expect(ring().color, const Color(0xffff665d));
      expect(find.text('4s'), findsOneWidget);
      // An unrelated rebuild must not refill or restart the ring.
      await show(tester, deadline: deadline);
      expect(ring().value, closeTo(.4, .03));
      await tester.pump(const Duration(seconds: 5));
      expect(ring().value, 0);
      expect(find.text('0s'), findsOneWidget);
      await show(tester, deadline: deadline, active: false);
      expect(find.byKey(const ValueKey('own-turn-progress')), findsNothing);
      expect(find.byKey(const ValueKey('own-turn-seconds')), findsNothing);
    },
  );

  testWidgets('a new turn resyncs and an expired deadline stays at zero', (
    tester,
  ) async {
    await show(
      tester,
      deadline: DateTime.now().add(const Duration(seconds: 8)),
    );
    await tester.pump(const Duration(seconds: 6));
    await show(
      tester,
      deadline: DateTime.now().add(const Duration(seconds: 15)),
    );
    final ring = tester.widget<CircularProgressIndicator>(
      find.byKey(const ValueKey('own-turn-progress')),
    );
    expect(ring.value, closeTo(1, .02));
    expect(ring.color, const Color(0xffffd166));
    await show(
      tester,
      deadline: DateTime.now().subtract(const Duration(seconds: 1)),
    );
    expect(find.text('0s'), findsOneWidget);
  });

  testWidgets('practice pulses finish without inventing a timer', (
    tester,
  ) async {
    await show(tester, deadline: null);
    expect(find.byKey(const ValueKey('own-turn-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('own-turn-seconds')), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion preserves real time and disposal stops updates', (
    tester,
  ) async {
    await show(
      tester,
      deadline: DateTime.now().add(const Duration(seconds: 10)),
      reduced: true,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('8s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 20));
    expect(tester.takeException(), isNull);
  });
}
