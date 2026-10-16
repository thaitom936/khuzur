import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:card/chat/chat_composer.dart';
import 'package:card/chat/chat_media_preview.dart';
import 'package:card/chat/chat_voice_controller.dart';
import 'package:card/l10n/strings.dart';
import 'package:card/net/net_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeVoiceCapture implements VoiceCapture {
  final levels = StreamController<double>.broadcast();
  Completer<bool>? permission;
  Completer<void>? starting;
  Completer<String?>? stopping;
  int starts = 0, cancels = 0, stops = 0, pauses = 0, resumes = 0;
  bool disposed = false;
  final closed = Completer<void>();
  @override
  Future<bool> hasPermission() async =>
      permission == null ? true : permission!.future;
  @override
  Future<void> start(String path) async {
    starts++;
    await starting?.future;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<void> pause() async {
    pauses++;
  }

  @override
  Future<void> resume() async {
    resumes++;
  }

  @override
  Future<String?> stop() async {
    stops++;
    return stopping == null ? '/missing-test-voice.m4a' : stopping!.future;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await levels.close();
    closed.complete();
  }

  @override
  Stream<double> get amplitude => levels.stream;
}

void main() {
  test('Denied permission never starts capture', () async {
    final capture = FakeVoiceCapture()
      ..permission = Completer<bool>()
      ..permission!.complete(false);
    final voice = ChatVoiceController(
      capture: capture,
      createPath: () async => '/missing-test-voice.m4a',
    );
    await expectLater(voice.start(), throwsA(isA<NetException>()));
    expect(capture.starts, 0);
    expect(voice.stage, VoiceStage.idle);
    voice.dispose();
  });

  test(
    'Cancel while requesting permission prevents later microphone start',
    () async {
      final capture = FakeVoiceCapture()..permission = Completer<bool>();
      final voice = ChatVoiceController(
        capture: capture,
        createPath: () async => '/missing-test-voice.m4a',
      );
      final starting = voice.start();
      await Future<void>.delayed(Duration.zero);
      final cancelled = voice.discard();
      capture.permission!.complete(true);
      await starting;
      await cancelled;
      expect(capture.starts, 0);
      expect(voice.stage, VoiceStage.idle);
      voice.dispose();
    },
  );

  test(
    'Disposal during a native start cancels it after start completes',
    () async {
      final capture = FakeVoiceCapture()..starting = Completer<void>();
      final voice = ChatVoiceController(
        capture: capture,
        createPath: () async => '/missing-test-voice.m4a',
      );
      final starting = voice.start();
      await Future<void>.delayed(Duration.zero);
      expect(capture.starts, 1);
      voice.dispose();
      capture.starting!.complete();
      await starting;
      await capture.closed.future;
      expect(capture.cancels, greaterThan(0));
      expect(capture.disposed, isTrue);
    },
  );

  test(
    'Pause excludes paused time, resumes the same draft and shows measured levels',
    () async {
      var now = DateTime.utc(2026);
      final capture = FakeVoiceCapture();
      final voice = ChatVoiceController(
        capture: capture,
        now: () => now,
        createPath: () async => '/missing-test-voice.m4a',
      );
      await voice.start();
      capture.levels.add(-12);
      await Future<void>.delayed(Duration.zero);
      expect(voice.samples.single, closeTo(.8, .001));
      now = now.add(const Duration(seconds: 5));
      await voice.togglePause();
      now = now.add(const Duration(seconds: 20));
      expect(voice.duration.inSeconds, 5);
      expect(capture.stops, 0);
      await voice.togglePause();
      now = now.add(const Duration(seconds: 3));
      expect(voice.duration.inSeconds, 8);
      await voice.finish();
      expect(voice.stage, VoiceStage.ready);
      expect(capture.starts, 1);
      expect(capture.stops, 1);
      await voice.discard();
      voice.dispose();
    },
  );

  testWidgets('60-second limit creates an unsent draft and releases capture', (
    tester,
  ) async {
    var now = DateTime.utc(2026);
    final capture = FakeVoiceCapture();
    final voice = ChatVoiceController(
      capture: capture,
      now: () => now,
      createPath: () async => '/missing-test-voice.m4a',
    );
    final start = voice.start();
    await tester.pump();
    await start;
    now = now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    expect(voice.stage, VoiceStage.ready);
    expect(voice.path, isNotNull);
    expect(capture.stops, 1);
    voice.dispose();
    await tester.pump();
  });

  test('Discard during stop cannot resurrect a cancelled draft', () async {
    final capture = FakeVoiceCapture()..stopping = Completer<String?>();
    final voice = ChatVoiceController(
      capture: capture,
      createPath: () async => '/missing-test-voice.m4a',
    );
    await voice.start();
    final stopped = voice.finish();
    await Future<void>.delayed(Duration.zero);
    final discarded = voice.discard();
    capture.stopping!.complete('/missing-test-voice.m4a');
    expect(await stopped, isNull);
    await discarded;
    expect(voice.stage, VoiceStage.idle);
    expect(voice.path, isNull);
    voice.dispose();
  });

  for (final mediaAllowed in [true, false]) {
    testWidgets(
      'Composer toggles mic/send, no plus, fits keyboard (media=$mediaAllowed)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final input = TextEditingController();
        final focus = FocusNode();
        final voice = ChatVoiceController(capture: FakeVoiceCapture());
        var sent = 0, camera = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: const ExpandedPlaceholder(),
              bottomNavigationBar: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQueryData.fromView(
                    tester.view,
                  ).viewInsets.bottom,
                ),
                child: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.5),
                  ),
                  child: ChatComposer(
                    l: const L('zh'),
                    input: input,
                    focus: focus,
                    voice: voice,
                    writable: true,
                    mediaAllowed: mediaAllowed,
                    voiceAllowed: true,
                    busy: false,
                    onSend: () => sent++,
                    onCamera: () => camera++,
                    onEmoji: () {},
                    onRecord: () {},
                    onDiscardVoice: () {},
                    onPauseVoice: () {},
                    onSendVoice: () {},
                    onPreviewVoice: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.add), findsNothing);
        expect(
          find.byKey(const Key('chat-mic')),
          mediaAllowed ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('chat-camera')),
          mediaAllowed ? findsOneWidget : findsNothing,
        );
        if (mediaAllowed) {
          await tester.tap(find.byKey(const Key('chat-camera')));
          expect(camera, 1);
        }
        expect(find.byKey(const Key('chat-gallery')), findsNothing);
        expect(find.byIcon(Icons.photo_library_outlined), findsNothing);
        await tester.enterText(find.byKey(const Key('chat-input')), 'Hello 你好');
        await tester.pump();
        expect(find.byKey(const Key('chat-mic')), findsNothing);
        expect(find.byKey(const Key('chat-camera')), findsNothing);
        await tester.tap(find.byKey(const Key('chat-send')));
        expect(sent, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        voice.dispose();
        input.dispose();
        focus.dispose();
        await tester.pump();
      },
    );
  }

  testWidgets('Photo preview requires explicit send and cancel returns false', (
    tester,
  ) async {
    final bytes = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
      ),
    );
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatMediaPreview(
                      bytes: bytes,
                      path: '/sample.png',
                      video: false,
                      l: const L('zh'),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.tap(find.byKey(const Key('chat-preview-cancel')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-preview-send')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });
}

class ExpandedPlaceholder extends StatelessWidget {
  const ExpandedPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
