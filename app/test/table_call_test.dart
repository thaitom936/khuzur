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
  Map<String, dynamic> rtc = {
    'enabled': false,
    'payer_uid': 0,
    'video_epoch': 0,
  };
  @override
  Stream<Map<String, dynamic>> get pushes => events.stream;
  @override
  Future<Map<String, dynamic>> call(
    String cmd, [
    Map<String, dynamic>? args,
  ]) async {
    requests.add({'cmd': cmd, ...?args});
    if (reply != null) return reply!();
    if (cmd == 'rtc_control') {
      if (args?['action'] == 'start') rtc['enabled'] = true;
      if (args?['action'] == 'prepare') {
        if (rtc['payer_uid'] == 0 && args?['consent'] != true) {
          throw NetException('rtc_payment_required');
        }
        rtc['payer_uid'] = 42;
      }
      return {'rtc': Map.of(rtc)};
    }
    return token();
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
  @override
  Future<void> muteAll(bool muted) async {
    actions.add('speaker:$muted');
  }
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
    call.dispose();
    await call.leave();
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
      await call.toggleDevice(camera: true, consent: true);
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
      await tester.tap(find.text('Unmute'));
      await tester.pumpAndSettle();
      expect(
        find.text('Table calls are not available yet. You can keep playing.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(transport.actions.where((a) => a.startsWith('join:')), isEmpty);
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

  test('first microphone enables table without payment', () async {
    await call.toggleDevice(camera: false);
    expect(call.connected, isTrue);
    expect(call.microphoneOn, isTrue);
    expect(game.rtcEnabled, isTrue);
    expect(
      session.client.requests.any((r) => r['action'] == 'prepare'),
      isFalse,
    );
  });

  test('room activation auto joins without permissions or capture', () async {
    session.client.rtc['enabled'] = true;
    game.updateRtc(Map.of(session.client.rtc));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(call.connected, isTrue);
    expect(transport.actions, ['join:42']);
    expect(call.cameraOn, isFalse);
    expect(call.microphoneOn, isFalse);
    expect(
      session.client.requests.any((r) => r['action'] == 'prepare'),
      isFalse,
    );
  });

  test('spectators never auto join', () async {
    game.humanSeat = -1;
    game.updateRtc({'enabled': true});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(transport.actions, isEmpty);
    expect(session.client.requests, isEmpty);
  });

  test('video requires consent before publication', () async {
    await call.toggleDevice(camera: true);
    expect(call.cameraOn, isFalse);
    expect(call.error, 'rtc_payment_required');
    await call.toggleDevice(camera: true, consent: true);
    expect(call.cameraOn, isTrue);
    expect(game.rtcPayer, 42);
    expect(session.client.requests.last['camera'], isTrue);
  });

  test(
    'billing stop disables camera but preserves microphone and call',
    () async {
      await call.toggleDevice(camera: false);
      await call.toggleDevice(camera: true, consent: true);
      session.client.rtc.addAll({
        'video_epoch': 1,
        'blocked': 'rtc_insufficient',
      });
      game.updateRtc(Map.of(session.client.rtc));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(call.cameraOn, isFalse);
      expect(call.microphoneOn, isTrue);
      expect(call.connected, isTrue);
      expect(transport.actions.last, 'camera:false');
    },
  );

  test('foreground reconnects receive only after background', () async {
    await call.toggleDevice(camera: true, consent: true);
    call.didChangeAppLifecycleState(AppLifecycleState.paused);
    await call.leave();
    expect(call.connected, isFalse);
    call.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(call.connected, isTrue);
    expect(call.cameraOn, isFalse);
    expect(call.microphoneOn, isFalse);
  });

  test('foreign room signal ignored; coin push updates balance', () async {
    session.client.events.add({
      'push': 'rtc_state',
      'code': '999999',
      'rtc': {'enabled': true},
    });
    session.client.events.add({'push': 'rtc_balance', 'coins': 12});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(game.rtcEnabled, isFalse);
    expect(session.user!.coins, 12);
    expect(call.connected, isFalse);
  });
}
