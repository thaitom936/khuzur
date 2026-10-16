import 'package:card/chat/chat_emoji_picker.dart';
import 'package:card/chat/chat_screen.dart';
import 'package:card/l10n/strings.dart';
import 'package:card/net/session.dart';
import 'package:card/settings/persistence/memory_settings_persistence.dart';
import 'package:card/settings/settings.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_test.dart' as fixtures;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Emoji insertion preserves the selected range and joined sequences', () {
    final input = TextEditingController(text: 'Hello world');
    addTearDown(input.dispose);
    const family = '👨‍👩‍👧‍👦';
    expect(
      insertChatEmoji(
        input,
        family,
        selection: const TextSelection(baseOffset: 6, extentOffset: 11),
      ),
      isTrue,
    );
    expect(input.text, 'Hello $family');
    expect(input.selection.baseOffset, 6 + family.length);
    expect(input.value.composing, TextRange.empty);
    expect(insertChatEmoji(input, '👍🏽'), isTrue);
    expect(input.text, 'Hello $family👍🏽');
    input.selection = const TextSelection.collapsed(offset: 0);
    expect(insertChatEmoji(input, '😀'), isTrue);
    expect(input.text, '😀Hello $family👍🏽');
  });

  test(
    'Missing cursor appends, and code-point limit rejects an entire emoji',
    () {
      final input = TextEditingController(text: 'x' * 498);
      addTearDown(input.dispose);
      expect(insertChatEmoji(input, '👍🏽'), isTrue);
      expect(input.text.runes.length, 500);
      final before = input.value;
      expect(insertChatEmoji(input, '😀'), isFalse);
      expect(input.value, before);
      expect(
        insertChatEmoji(
          input,
          '😀',
          selection: const TextSelection(baseOffset: 0, extentOffset: 2),
        ),
        isTrue,
      );
      expect(input.text.runes.length, 499);
    },
  );

  testWidgets(
    'Shared chat picker inserts at cursor, saves recents and searches',
    (tester) async {
      final session = fixtures.ChatSession();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<Session>.value(value: session),
            Provider(
              create: (_) =>
                  SettingsController(store: MemoryOnlySettingsPersistence()),
            ),
          ],
          child: const MaterialApp(
            home: ChatScreen(channel: 'lobby:en', title: 'Lobby chat'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final inputFinder = find.byKey(const Key('chat-input'));
      await tester.enterText(inputFinder, 'Hello world');
      final controller = tester.widget<TextField>(inputFinder).controller!;
      controller.selection = const TextSelection(
        baseOffset: 6,
        extentOffset: 11,
      );
      await tester.tap(find.byKey(const Key('chat-emoji')));
      await tester.pumpAndSettle();
      expect(find.byType(EmojiPicker), findsOneWidget);
      await tester.tap(find.text('😀').first);
      await tester.pumpAndSettle();
      expect(controller.text, 'Hello 😀');
      expect(controller.selection.baseOffset, 8);
      expect(
        (await EmojiPickerUtils().getRecentEmojis()).any(
          (e) => e.emoji.emoji == '😀',
        ),
        isTrue,
      );
      await tester.tap(find.byKey(const Key('chat-emoji')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.access_time));
      await tester.pumpAndSettle();
      expect(find.text('😀'), findsWidgets);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      final search = find.descendant(
        of: find.byType(DefaultSearchView),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'grinning');
      await tester.pumpAndSettle();
      expect(find.text('😀'), findsWidgets);
      await tester.tap(find.text('😀').first);
      await tester.pumpAndSettle();
      expect(controller.text, 'Hello 😀😀');
      expect(
        session.fake.commands.where((c) => c['cmd'] == 'chat_send'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await session.fake.events.close();
      session.dispose();
    },
  );

  for (final size in [const Size(320, 568), const Size(355, 486)]) {
    testWidgets(
      'Localized emoji search fits keyboard and large text at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showModalBottomSheet<String>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const ChatEmojiPickerSheet(l: L('zh')),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EmojiPicker>(find.byType(EmojiPicker))
              .config
              .locale
              .languageCode,
          'zh',
        );
        await tester.tap(find.byIcon(Icons.search));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        expect(find.text('搜索表情'), findsOneWidget);
        final search = find.descendant(
          of: find.byType(DefaultSearchView),
          matching: find.byType(TextField),
        );
        await tester.enterText(search, '笑脸');
        await tester.pumpAndSettle();
        expect(find.text('😀'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('chat-emoji-close')));
        await tester.pumpAndSettle();
        expect(find.byType(EmojiPicker), findsNothing);
      },
    );
  }
}
