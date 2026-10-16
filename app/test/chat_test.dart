import 'dart:async';

import 'package:card/chat/chat_audio_waveform.dart';
import 'package:card/chat/chat_controller.dart';
import 'package:card/chat/chat_screen.dart';
import 'package:card/net/net_client.dart';
import 'package:card/net/session.dart';
import 'package:card/settings/persistence/memory_settings_persistence.dart';
import 'package:card/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class Client extends NetClient {
  Client() {
    state.value = ConnState.online;
  }
  final events = StreamController<Map<String, dynamic>>.broadcast();
  final commands = <Map<String, dynamic>>[];
  final responses = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? sendRequest;
  Completer<Map<String, dynamic>>? openRequest;
  @override
  Stream<Map<String, dynamic>> get pushes => events.stream;
  @override
  Future<Map<String, dynamic>> call(
    String cmd, [
    Map<String, dynamic>? args,
  ]) async {
    commands.add({'cmd': cmd, ...?args});
    if (cmd == 'chat_open' || cmd == 'chat_history') {
      if (openRequest != null) return openRequest!.future;
      return responses.isEmpty
          ? {
              'messages': [],
              'has_more': false,
              'capabilities': {'media': false, 'write': true},
            }
          : responses.removeAt(0);
    }
    if (cmd == 'chat_send') {
      return sendRequest!.future;
    }
    return {};
  }
}

class ChatSession extends Session {
  final fake = Client();
  @override
  Client get client => fake;
}

void main() {
  for (final sample in [
    (body: 'ok', scale: 1.0),
    (body: '长消息需要自动换行，时间不能遮挡文字。' * 12, scale: 2.0),
    (body: 'https://example.com/${'a' * 180}', scale: 1.5),
  ]) {
    testWidgets(
      'Bubble fits content and timestamp never overlaps (${sample.scale}, ${sample.body.length})',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = ChatSession();
        final sentAt =
            DateTime(2026, 10, 16, 10, 16).millisecondsSinceEpoch ~/ 1000;
        session.fake.responses.add({
          'messages': [
            {
              'id': 1,
              'uid': 2,
              'name': 'Bataa',
              'body': sample.body,
              'created_at': sentAt,
            },
          ],
          'capabilities': {'media': false, 'write': true},
        });
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<Session>.value(value: session),
              Provider(
                create: (_) =>
                    SettingsController(store: MemoryOnlySettingsPersistence()),
              ),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(sample.scale)),
                child: child!,
              ),
              home: const ChatScreen(channel: 'lobby:en', title: 'Chat'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final bubble = tester.getRect(find.byType(Card));
        final timestamp = tester.getRect(find.text('10:16'));
        expect(timestamp.right, closeTo(bubble.right - 10, 1));
        expect(timestamp.bottom, closeTo(bubble.bottom - 6, 1));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byWidgetPredicate(
            (w) =>
                w is RichText && w.text.toPlainText().startsWith(sample.body),
          ),
        );
        for (final box in paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: sample.body.length),
        )) {
          final rect = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
          expect(rect.overlaps(timestamp), isFalse);
        }
        if (sample.body == 'ok') {
          expect(bubble.width, lessThan(120));
          expect(bubble.height, lessThan(40));
          expect(
            tester.getRect(find.text('Bataa')).bottom,
            lessThan(bubble.top),
          );
        }
        await tester.pumpWidget(const SizedBox());
        await session.fake.events.close();
        session.dispose();
      },
    );
  }
  testWidgets('Delayed history restores saved chat position and draft', (
    tester,
  ) async {
    final session = ChatSession();
    session.chatDrafts['club:1'] = 'Keep this draft';
    session.chatScrollOffsets['club:1'] = 100;
    session.fake.openRequest = Completer();
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
          home: ChatScreen(channel: 'club:1', title: 'Club chat'),
        ),
      ),
    );
    await tester.pump();
    expect(session.chatScrollOffsets['club:1'], 100);
    session.fake.openRequest!.complete({
      'messages': [
        for (var i = 1; i <= 30; i++)
          {
            'id': i,
            'uid': 2,
            'nonce': '$i',
            'body': 'Earlier message $i',
            'name': 'Bataa',
          },
      ],
      'capabilities': {'write': true, 'media': false},
    });
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.controller!.offset, 100);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chat-input')))
          .controller!
          .text,
      'Keep this draft',
    );
    await tester.pumpWidget(const SizedBox());
    await session.fake.events.close();
    session.dispose();
  });
  test(
    'Disconnected chat cannot send and recovers its permission on reconnect',
    () async {
      final client = Client();
      final chat = ChatController(client, 'lobby:en');
      addTearDown(chat.dispose);
      addTearDown(client.events.close);
      await chat.open();
      expect(chat.writable, isTrue);
      client.state.value = ConnState.offline;
      expect(chat.writable, isFalse);
      await chat.send('must stay unsent');
      expect(client.commands.where((c) => c['cmd'] == 'chat_send'), isEmpty);
      client.state.value = ConnState.online;
      await Future<void>.delayed(Duration.zero);
      expect(chat.writable, isTrue);
    },
  );
  test(
    'Retries keep the nonce and an early push prevents duplicate bubbles',
    () async {
      final client = Client();
      final chat = ChatController(client, 'club:1');
      addTearDown(chat.dispose);
      addTearDown(client.events.close);
      await chat.open();
      client.sendRequest = Completer();
      final sending = chat.send('Hello 😀', uid: 1, nonce: 'retry123');
      expect(chat.pending['retry123']!['state'], 'sending');
      client.sendRequest!.completeError(NetException('timeout'));
      await sending;
      expect(chat.pending['retry123']!['state'], 'failed');
      client.sendRequest = Completer();
      final retry = chat.send('Hello 😀', uid: 1, nonce: 'retry123');
      final row = {'id': 1, 'uid': 1, 'nonce': 'retry123', 'body': 'Hello 😀'};
      client.events.add({
        'push': 'chat_message',
        'channel': 'club:1',
        'message': row,
      });
      await Future<void>.delayed(Duration.zero);
      expect(chat.pending, isEmpty);
      expect(chat.messages.length, 1);
      client.sendRequest!.complete({'message': row});
      await retry;
      expect(chat.messages.length, 1);
      expect(
        client.commands
            .where((c) => c['cmd'] == 'chat_send')
            .map((c) => c['nonce']),
        ['retry123', 'retry123'],
      );
    },
  );
  test(
    'Reconnect catches every page, isolates channels and applies deletion',
    () async {
      final client = Client();
      final chat = ChatController(client, 'club:1');
      addTearDown(chat.dispose);
      addTearDown(client.events.close);
      client.responses.add({
        'messages': [
          {'id': 1, 'uid': 1, 'nonce': 'a', 'body': 'old'},
        ],
        'capabilities': {'write': true},
        'has_more': false,
      });
      await chat.open();
      client.responses.addAll([
        {
          'messages': [
            {'id': 2, 'uid': 2, 'nonce': 'b', 'body': 'next'},
          ],
          'has_more': true,
        },
        {
          'messages': [
            {'id': 3, 'uid': 3, 'nonce': 'c', 'body': 'last'},
          ],
          'has_more': false,
        },
      ]);
      await chat.open(reconnect: true);
      expect(chat.messages.map((m) => m['id']), [1, 2, 3]);
      expect(client.commands.last['after'], 2);
      client.events.add({
        'push': 'chat_message',
        'channel': 'club:2',
        'message': {'id': 4},
      });
      client.events.add({'push': 'chat_deleted', 'channel': 'club:1', 'id': 2});
      await Future<void>.delayed(Duration.zero);
      expect(chat.messages.length, 3);
      expect(chat.messages[1]['deleted'], isTrue);
      client.events.add({'push': 'chat_closed', 'channel': 'club:1'});
      await Future<void>.delayed(Duration.zero);
      expect(chat.writable, isFalse);
    },
  );
  for (final readOnly in [false, true]) {
    testWidgets(
      'Chat text, expired media and composer fit phone (readOnly=$readOnly)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = ChatSession();
        session.fake.responses.add({
          'messages': [
            {
              'id': 1,
              'uid': 2,
              'nonce': 'a',
              'body': 'Hello world 😀',
              'name': 'A long member name',
              'created_at': 100,
              'media': {
                'id': 'expired',
                'kind': 'image',
                'expired': true,
                'expires_at': 1,
              },
            },
            {
              'id': 2,
              'uid': 2,
              'nonce': 'voice',
              'body': '',
              'name': 'Bataa',
              'created_at': 101,
              'media': {
                'id': 'voice',
                'kind': 'audio',
                'duration': 60,
                'expires_at':
                    DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              },
            },
          ],
          'capabilities': {'media': true, 'write': !readOnly},
          'has_more': false,
        });
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<Session>.value(value: session),
              Provider(
                create: (_) =>
                    SettingsController(store: MemoryOnlySettingsPersistence()),
              ),
            ],
            child: MaterialApp(
              builder: (c, w) => MediaQuery(
                data: MediaQuery.of(
                  c,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: w!,
              ),
              home: const ChatScreen(channel: 'club:1', title: 'Club chat'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('File expired (kept for 7 days)'), findsOneWidget);
        expect(find.byType(ChatAudioWaveform), findsOneWidget);
        final voiceBubble = tester.getSize(
          find.ancestor(
            of: find.byType(ChatAudioWaveform),
            matching: find.byType(Card),
          ),
        );
        // Includes 1.5x accessibility text: still compact within the phone row.
        expect(voiceBubble.width, lessThan(240));
        expect(voiceBubble.height, lessThan(50));
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          !readOnly,
        );
        await tester.pumpWidget(const SizedBox());
        await session.fake.events.close();
        session.dispose();
      },
    );
  }
}
