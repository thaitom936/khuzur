import 'package:card/audio/audio_controller.dart';
import 'package:card/audio/sounds.dart';
import 'package:card/chat/chat_composer.dart';
import 'package:card/chat/chat_screen.dart';
import 'package:card/game/game_controller.dart';
import 'package:card/game/remote_game.dart';
import 'package:card/l10n/strings.dart';
import 'package:card/net/session.dart';
import 'package:card/play_session/play_session_screen.dart';
import 'package:card/play_session/turn_countdown_avatar.dart';
import 'package:card/rtc/table_call_controller.dart';
import 'package:card/rules/rules.dart';
import 'package:card/settings/persistence/memory_settings_persistence.dart';
import 'package:card/settings/settings.dart';
import 'package:card/style/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'chat_test.dart' show ChatSession;

class _SilentAudio implements AudioController {
  @override
  void playSfx(SfxType type) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets(
      'Table chat is translucent, keeps drafts and does not leave the table at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final session = ChatSession();
        final game = RemoteGameController(session)
          ..started = true
          ..roomCode = '123456'
          ..chatChannel = 'table:drawer'
          ..numPlayers = 2
          ..humanSeat = 0
          ..seats = List.generate(
            2,
            (i) => SeatView(
              name: 'Player $i',
              score: 15,
              tricks: 0,
              decision: Decision.play,
            ),
          );
        final call = TableCallController(session, game, supported: false);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider(
                create: (_) =>
                    SettingsController(store: MemoryOnlySettingsPersistence()),
              ),
              Provider(create: (_) => Palette()),
              Provider<AudioController>(create: (_) => _SilentAudio()),
              ChangeNotifierProvider<Session>.value(value: session),
              ChangeNotifierProvider<GameController>.value(value: game),
              ChangeNotifierProvider<TableCallController>.value(value: call),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: const TableView(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final toolbar = find.byKey(
          const ValueKey('table-communication-controls'),
        );
        await tester.ensureVisible(toolbar);
        await tester.pumpAndSettle();
        final barRect = tester.getRect(toolbar);
        expect(barRect.top, greaterThan(size.height * .45));
        expect(barRect.bottom, lessThan(size.height - 160));
        expect(
          barRect.bottom,
          lessThan(
            tester.getRect(find.byKey(const ValueKey('table-hand'))).top,
          ),
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('table-seat-0'))).bottom,
          lessThanOrEqualTo(barRect.top),
        );
        expect(find.byIcon(Icons.forum_outlined).hitTestable(), findsOneWidget);
        expect(
          find.byIcon(Icons.videocam_outlined).hitTestable(),
          findsOneWidget,
        );
        expect(
          tester.getCenter(find.byIcon(Icons.forum_outlined)).dx,
          lessThan(size.width / 2),
        );
        expect(
          tester.getCenter(find.byIcon(Icons.videocam_outlined)).dx,
          lessThan(size.width / 2),
        );
        await tester.tap(find.byIcon(Icons.videocam_outlined));
        await tester.pumpAndSettle();
        expect(find.text(L('en')('rtcTitle')), findsOneWidget);
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.forum_outlined));
        await tester.pumpAndSettle();
        expect(find.byType(Drawer), findsOneWidget);
        expect(find.byType(TableView), findsOneWidget);
        final drawer = tester.widget<Drawer>(find.byType(Drawer));
        expect(drawer.backgroundColor!.a, inExclusiveRange(0, 1));
        expect(tester.getRect(find.byType(Drawer)).left, 0);
        expect(tester.getSize(find.byType(Drawer)).width, lessThan(size.width));
        final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
        expect(chat.embedded, isTrue);
        expect(chat.translucent, isTrue);
        expect(chat.active, isTrue);
        expect(
          tester.widget<ChatComposer>(find.byType(ChatComposer)).translucent,
          isTrue,
        );
        expect(find.byType(AppBar), findsNothing);
        await tester.enterText(
          find.byKey(const Key('chat-input')),
          'unsent table draft',
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final input = tester.getRect(find.byKey(const Key('chat-input')));
        expect(input.bottom, lessThanOrEqualTo(size.height - 220));
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        game.turn = 0;
        game.turnDuration = const Duration(seconds: 15);
        game.turnDeadline = DateTime.now().add(const Duration(seconds: 15));
        game.notifyListeners();
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        final sweep =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('own-turn-progress')),
                    )
                    .painter!
                as AvatarCooldownPainter;
        expect(sweep.progress, lessThan(1));
        await tester.tap(find.byKey(const Key('table-chat-close')));
        await tester.pumpAndSettle();
        expect(game.roomCode, '123456');
        expect(session.chatDrafts['table:drawer'], 'unsent table draft');
        await tester.ensureVisible(find.byIcon(Icons.forum_outlined));
        await tester.tap(find.byIcon(Icons.forum_outlined));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('chat-input')))
              .controller!
              .text,
          'unsent table draft',
        );
        await tester.tap(find.byKey(const Key('table-chat-quick-toggle')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.widgetWithText(TextButton, L('en').phrases.first),
        );
        await tester.pumpAndSettle();
        expect(
          session.fake.commands.where((c) => c['cmd'] == 'chat'),
          hasLength(1),
        );
        await tester.ensureVisible(find.byIcon(Icons.forum_outlined));
        await tester.tap(find.byIcon(Icons.forum_outlined));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        final scaffold = tester.state<ScaffoldState>(
          find.byWidgetPredicate((w) => w is Scaffold && w.drawer != null),
        );
        expect(scaffold.isDrawerOpen, isFalse);
        expect(
          session.fake.commands.where(
            (c) => c['cmd'] == 'leave_room' || c['cmd'] == 'dissolve_room',
          ),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox());
        call.dispose();
        game.dispose();
        session.dispose();
        await session.fake.events.close();
      },
    );
  }
}
