import 'package:card/main.dart';
import 'package:card/play_session/card_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('smoke test', (tester) async {
    // Build our game and trigger a frame.
    await tester.pumpWidget(MyApp());

    // Verify that the main menu buttons are shown.
    expect(find.text('Single player'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Go to 'Settings'.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Music'), findsOneWidget);

    // Go back to main menu.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    // Tap 'Single player': the table appears with trump card and hand.
    await tester.tap(find.text('Single player'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CardView), findsWidgets);

    // Back to the main menu.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Single player'), findsOneWidget);

    // Let the bot loop notice the controller is disposed so no timers leak.
    await tester.pump(const Duration(seconds: 3));
  });
}
