import 'package:card/play_session/turn_countdown_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(
    WidgetTester tester, {
    required DateTime? deadline,
    bool active = true,
    bool reduced = false,
    Size? frameSize,
    Duration? duration,
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
              frameSize: frameSize,
              duration: duration,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  AvatarCooldownPainter sweep(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(
                find.byKey(const ValueKey('own-turn-progress')),
              )
              .painter!
          as AvatarCooldownPainter;

  for (final frame in [null, const Size(96, 112)]) {
    testWidgets(
      'Avatar overlay counts down within the portrait and warns at five ($frame)',
      (tester) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        await show(tester, deadline: deadline, frameSize: frame);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(sweep(tester).circular, frame == null);
        expect(
          tester.getSize(find.byKey(const ValueKey('own-turn-progress'))),
          frame == null ? const Size(46, 46) : const Size(88, 104),
        );
        expect(sweep(tester).progress, closeTo(1, .02));
        await tester.pump(const Duration(seconds: 10));
        expect(sweep(tester).progress, closeTo(1 / 3, .03));
        expect(sweep(tester).color, const Color(0xffff665d));
        expect(find.text('5s'), findsOneWidget);
        // An unrelated rebuild must not refill or restart the sweep.
        await show(tester, deadline: deadline, frameSize: frame);
        expect(sweep(tester).progress, closeTo(1 / 3, .03));
        await tester.pump(const Duration(seconds: 6));
        expect(sweep(tester).progress, 0);
        expect(find.text('0s'), findsOneWidget);
        await show(tester, deadline: deadline, active: false, frameSize: frame);
        expect(find.byKey(const ValueKey('own-turn-progress')), findsNothing);
        expect(find.byKey(const ValueKey('own-turn-seconds')), findsNothing);
      },
    );
  }

  testWidgets(
    'Late entry uses the remaining fraction of the 15-second budget',
    (tester) async {
      final deadline = DateTime.now().add(const Duration(seconds: 7));
      await show(
        tester,
        deadline: deadline,
        duration: const Duration(seconds: 15),
      );
      expect(sweep(tester).progress, closeTo(7 / 15, .02));
      expect(find.text('7s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(sweep(tester).progress, closeTo(5 / 15, .02));
      expect(find.text('5s'), findsOneWidget);
      expect(sweep(tester).color, const Color(0xffff665d));
      await show(
        tester,
        deadline: deadline,
        duration: const Duration(seconds: 15),
      );
      expect(sweep(tester).progress, closeTo(5 / 15, .02));
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
    expect(sweep(tester).progress, closeTo(1, .02));
    expect(sweep(tester).color, const Color(0xffd5fff6));
    await show(
      tester,
      deadline: DateTime.now().subtract(const Duration(seconds: 1)),
    );
    expect(find.text('0s'), findsOneWidget);
  });

  testWidgets('practice entry rotation finishes without inventing a timer', (
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
