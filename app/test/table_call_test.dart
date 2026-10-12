import 'dart:async';

import 'package:card/game/game_controller.dart';
import 'package:card/game/remote_game.dart';
import 'package:card/net/net_client.dart';
import 'package:card/net/session.dart';
import 'package:card/rtc/agora_transport.dart';
import 'package:card/rtc/table_call_controller.dart';
import 'package:card/rtc/table_call_widgets.dart';
import 'package:card/rules/rules.dart';
import 'package:card/settings/persistence/memory_settings_persistence.dart';
import 'package:card/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> token([String channel = 'room-private']) => {
  'app_id': 'test-app',
  'channel': channel,
  'uid': 42,
  'token': 'test-token',
  'renew_after': 240,
};

class _Client extends NetClient {
  final events = StreamController<Map<String, dynamic>>.broadcast();
  final requests = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> Function()? reply;
  @override
  Stream<Map<String, dynamic>> get pushes => events.stream;
  @override
  Future<Map<String, dynamic>> call(
    String cmd, [
    Map<String, dynamic>? args,
  ]) async {
    requests.add({'cmd': cmd, ...?args});
    return reply == null ? token() : reply!();
  }
}

class _Session extends Session {
  final _client = _Client();
  @override
  _Client get client => _client;
}

class _Transport extends CallTransport {
  final actions = <String>[];
  bool permitted = true;
  Completer<bool>? waitingPermission;
  Completer<void>? waitingJoin;
  @override
  Future<void> connect(CallGrant grant) async {
    actions.add('join:${grant.uid}');
    await waitingJoin?.future;
  }

  @override
  Future<bool> permission({required bool camera}) async {
    actions.add('permission:$camera');
    return waitingPermission == null ? permitted : waitingPermission!.future;
  }

  @override
  Future<void> microphone(bool enabled) async {
    actions.add('mic:$enabled');
  }

  @override
  Future<void> camera(bool enabled) async {
    actions.add('camera:$enabled');
  }

  @override
  Future<void> renew(String token) async {
    actions.add('renew');
  }

  @override
  Future<void> close() async {
    actions.add('close');
  }

  @override
  Future<void> mutePeer(int uid, bool muted) async {
    actions.add('mute:$uid:$muted');
  }

  @override
  Future<void> switchCamera() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Session session;
  late RemoteGameController game;
  late _Transport transport;
  late TableCallController call;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    session = _Session()
      ..user = UserInfo(
        uid: 42,
        name: 'Me',
        games: 0,
        wins: 0,
        coins: 0,
        rating: 0,
        level: 1,
      );
    session.client.state.value = ConnState.online;
    game = RemoteGameController(session)
      ..roomCode = '123456'
      ..humanSeat = 0
      ..seats = [
        const SeatView(
          name: 'Me',
          score: 20,
          tricks: 0,
          decision: Decision.none,
          rtcUid: 42,
        ),
      ];
    transport = _Transport();
    call = TableCallController(
      session,
      game,
      supported: true,
      createTransport: () => transport,
    );
  });
  tearDown(() async {
    await call.leave();
    call.dispose();
    game.dispose();
    await session.client.events.close();
  });

  test(
    'join listens without device permissions or capture; server chooses identity',
    () async {
      expect(transport.actions, isEmpty);
      await call.join();
      expect(call.connected, isTrue);
      expect(call.microphoneOn, isFalse);
      expect(call.cameraOn, isFalse);
      expect(transport.actions, ['join:42']);
      expect(session.client.requests.single, {
        'cmd': 'rtc_token',
        'code': '123456',
      });
    },
  );

  test('spectators cannot join or request a token', () async {
    game.humanSeat = -1;
    await call.join();
    expect(session.client.requests, isEmpty);
  });

  test(
    'denied permission preserves listening and never starts capture',
    () async {
      await call.join();
      transport.permitted = false;
      await call.toggleDevice(camera: false);
      expect(call.connected, isTrue);
      expect(call.error, 'rtc_mic_permission');
      expect(transport.actions, ['join:42', 'permission:false']);
    },
  );

  test(
    'camera and microphone are independently enabled and disabled',
    () async {
      await call.join();
      await call.toggleDevice(camera: false);
      expect(call.microphoneOn, isTrue);
      expect(call.cameraOn, isFalse);
      await call.toggleDevice(camera: true);
      await call.toggleDevice(camera: false);
      expect(call.microphoneOn, isFalse);
      expect(call.cameraOn, isTrue);
      expect(
        transport.actions.where((s) => s.startsWith('permission')).length,
        2,
      );
    },
  );

  test(
    'leaving while a permission dialog is open cannot enable capture later',
    () async {
      await call.join();
      transport.waitingPermission = Completer<bool>();
      final toggle = call.toggleDevice(camera: true);
      final leaving = call.leave();
      transport.waitingPermission!.complete(true);
      await toggle;
      await leaving;
      expect(call.cameraOn, isFalse);
      expect(transport.actions, ['join:42', 'permission:true', 'close']);
    },
  );

  test(
    'late token after leave is discarded without creating a native engine',
    () async {
      final response = Completer<Map<String, dynamic>>();
      session.client.reply = () => response.future;
      final joining = call.join();
      final leaving = call.leave();
      response.complete(token());
      await joining;
      await leaving;
      expect(transport.actions, isEmpty);
      expect(call.connected, isFalse);
    },
  );

  test(
    'native join completing after leave releases engine exactly once',
    () async {
      transport.waitingJoin = Completer<void>();
      final joining = call.join();
      await Future<void>.delayed(Duration.zero);
      final leaving = call.leave();
      transport.waitingJoin!.complete();
      await joining;
      await leaving;
      expect(transport.actions, ['join:42', 'close']);
      expect(call.connected, isFalse);
    },
  );

  testWidgets(
    'small screen shows unconfigured service without creating an engine',
    (tester) async {
      tester.view.physicalSize = const Size(355, 486);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      session.client.reply = () async => throw NetException('rtc_unavailable');
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider(
              create: (_) =>
                  SettingsController(store: MemoryOnlySettingsPersistence()),
            ),
            ChangeNotifierProvider<TableCallController>.value(value: call),
          ],
          child: const MaterialApp(home: Scaffold(body: TableCallButton())),
        ),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join audio'));
      await tester.pumpAndSettle();
      expect(
        find.text('Table calls are not available yet. You can keep playing.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(transport.actions, isEmpty);
      await call.leave();
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('game connection loss closes media and never auto-rejoins', () async {
    await call.join();
    session.client.state.value = ConnState.offline;
    await call.leave();
    session.client.state.value = ConnState.online;
    expect(call.connected, isFalse);
    expect(transport.actions, ['join:42', 'close']);
  });

  test('renewal is room-bound, rejected renewal tears down the call', () async {
    await call.join();
    await call.renew();
    expect(transport.actions.last, 'renew');
    session.client.reply = () async => token('different-room');
    await call.renew();
    await call.leave();
    expect(transport.actions.last, 'close');
    expect(call.connected, isFalse);
  });

  test(
    'background exit resets device state and ignores late SDK events',
    () async {
      await call.join();
      await call.toggleDevice(camera: false);
      call.didChangeAppLifecycleState(AppLifecycleState.paused);
      await call.leave();
      transport.onVideo?.call(43, true);
      transport.onConnection?.call(true);
      expect(call.microphoneOn, isFalse);
      expect(call.videos, isEmpty);
      expect(call.reconnecting, isFalse);
    },
  );
}
