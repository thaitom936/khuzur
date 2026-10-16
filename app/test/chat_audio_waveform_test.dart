import 'package:card/chat/chat_audio_waveform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Voice waveform animates only during visible playback', (
    tester,
  ) async {
    Future<void> show({
      required bool playing,
      bool visible = true,
      bool reducedMotion = false,
    }) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: TickerMode(
            enabled: visible,
            child: Center(child: ChatAudioWaveform(playing: playing)),
          ),
        ),
      ),
    );

    await show(playing: false);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.getSize(find.byType(ChatAudioWaveform)), const Size(40, 18));

    await show(playing: true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await show(playing: false);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);

    await show(playing: true, visible: false);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);

    await show(playing: true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await show(playing: true, reducedMotion: true);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);

    await show(playing: true);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
