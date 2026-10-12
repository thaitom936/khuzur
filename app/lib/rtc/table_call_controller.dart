import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../game/remote_game.dart';
import '../net/net_client.dart';
import '../net/session.dart';
import 'agora_transport.dart';

/// One call belongs to one visible table. Reconnection never enables devices
/// automatically. Game websocket failure tears down media independently.
class TableCallController extends ChangeNotifier with WidgetsBindingObserver {
  final Session session;
  final RemoteGameController game;
  final CallTransport Function() createTransport;
  final bool supported;
  final void Function(bool active)? onCallActive;
  late final StreamSubscription<Map<String, dynamic>> _pushes;
  CallTransport? transport;
  CallGrant? grant;
  bool connected = false, microphoneOn = false, cameraOn = false;
  bool busy = false, closing = false, reconnecting = false, weakNetwork = false;
  String? error;
  final Set<int> videos = {}, muted = {};
  final Map<int, DateTime> _speaking = {};
  Timer? _renewal, _levels;
  Future<void>? _pending, _leaveFuture;
  int _generation = 0;
  bool _disposed = false;
  String? _room;

  TableCallController(
    this.session,
    this.game, {
    CallTransport Function()? createTransport,
    this.onCallActive,
    bool? supported,
  }) : createTransport = createTransport ?? AgoraTransport.new,
       supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    game.addListener(_checkMembership);
    session.client.state.addListener(_checkMembership);
    _pushes = session.client.pushes.listen((msg) {
      if (msg['push'] == 'kick') unawaited(leave());
    });
    WidgetsBinding.instance.addObserver(this);
  }

  bool get available =>
      supported &&
      session.loggedIn &&
      !game.spectating &&
      !game.gameOver &&
      game.roomCode != null &&
      game.humanSeat < game.seats.length &&
      !game.seats[game.humanSeat].bot;

  bool speaking(int uid) =>
      !muted.contains(uid) &&
      (uid != grant?.uid || microphoneOn) &&
      (_speaking[uid]?.isAfter(
            DateTime.now().subtract(const Duration(milliseconds: 800)),
          ) ??
          false);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation) =>
      !_disposed && generation == _generation && !closing;

  void _checkMembership() {
    if ((transport != null || busy) && (!available || game.roomCode != _room)) {
      unawaited(leave());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android permission dialogs are 'inactive'; do not cancel those dialogs.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(leave());
    }
  }

  Future<void> _run(Future<void> Function(int) action) {
    if (busy || closing || _disposed) return Future.value();
    final generation = _generation;
    busy = true;
    error = null;
    _notify();
    final operation = () async {
      try {
        await action(generation);
      } catch (e) {
        if (_current(generation)) {
          error = e is NetException ? e.code : 'rtc_failed';
          // A partially successful device operation must never keep capturing.
          unawaited(leave());
        }
      } finally {
        _pending = null;
        busy = false;
        _notify();
      }
    }();
    _pending = operation;
    return operation;
  }

  Future<void> join() => _run((generation) async {
    if (!available || connected) return;
    _room = game.roomCode;
    onCallActive?.call(true);
    final response = await session.client.call('rtc_token', {'code': _room});
    if (!_current(generation)) return;
    final next = CallGrant.fromJson(response);
    final driver = transport = createTransport();
    grant = next;
    driver.onVideo = (uid, enabled) {
      if (!_current(generation)) return;
      enabled ? videos.add(uid) : videos.remove(uid);
      _notify();
    };
    driver.onLevels = (levels) {
      if (!_current(generation)) return;
      for (final entry in levels.entries) {
        if (entry.value > 8) _speaking[entry.key] = DateTime.now();
      }
    };
    driver.onConnection = (value) {
      if (!_current(generation)) return;
      reconnecting = value;
      _notify();
    };
    driver.onQuality = (value) {
      if (!_current(generation)) return;
      weakNetwork = value;
      _notify();
    };
    driver.onRenew = () {
      if (_current(generation)) unawaited(renew());
    };
    driver.onFailure = () {
      if (!_current(generation)) return;
      error = 'rtc_failed';
      unawaited(leave());
    };
    await driver.connect(next);
    if (!_current(generation)) return;
    connected = true;
    _scheduleRenewal(next);
    _levels = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _notify(),
    );
  });

  void _scheduleRenewal(CallGrant next) {
    _renewal?.cancel();
    _renewal = Timer(
      Duration(seconds: next.renewAfter.clamp(15, 240)),
      () => unawaited(renew()),
    );
  }

  Future<void> renew() async {
    if (!connected || closing) return;
    if (busy) {
      _renewal?.cancel();
      _renewal = Timer(const Duration(seconds: 2), () => unawaited(renew()));
      return;
    }
    await _run((generation) async {
      final next = CallGrant.fromJson(
        await session.client.call('rtc_token', {'code': _room}),
      );
      if (!_current(generation)) return;
      if (next.channel != grant?.channel || next.uid != grant?.uid) {
        throw StateError('room changed');
      }
      await transport!.renew(next.token);
      if (_current(generation)) _scheduleRenewal(next);
    });
  }

  Future<void> toggleDevice({required bool camera}) => _run((generation) async {
    if (!connected) return;
    final enable = !(camera ? cameraOn : microphoneOn);
    if (enable && !await transport!.permission(camera: camera)) {
      if (_current(generation)) {
        error = camera ? 'rtc_camera_permission' : 'rtc_mic_permission';
      }
      return;
    }
    if (!_current(generation)) return;
    if (camera) {
      await transport!.camera(enable);
      if (_current(generation)) cameraOn = enable;
    } else {
      await transport!.microphone(enable);
      if (_current(generation)) microphoneOn = enable;
    }
  });

  Future<void> toggleMute(int uid) => _run((generation) async {
    if (!connected) return;
    final enable = !muted.contains(uid);
    await transport!.mutePeer(uid, enable);
    if (_current(generation)) enable ? muted.add(uid) : muted.remove(uid);
  });

  Future<void> switchCamera() => _run((_) async {
    if (connected && cameraOn) await transport!.switchCamera();
  });

  Future<void> leave() {
    if (closing) return _leaveFuture ?? Future.value();
    ++_generation;
    closing = true;
    connected = microphoneOn = cameraOn = false;
    reconnecting = weakNetwork = false;
    videos.clear();
    muted.clear();
    _speaking.clear();
    _renewal?.cancel();
    _levels?.cancel();
    _notify();
    final pending = _pending;
    return _leaveFuture = () async {
      await pending;
      final driver = transport;
      transport = null;
      grant = null;
      try {
        await driver?.close();
      } catch (_) {
        error ??= 'rtc_failed';
      } finally {
        closing = false;
        onCallActive?.call(false);
        _notify();
      }
    }();
  }

  @override
  void dispose() {
    _disposed = true;
    game.removeListener(_checkMembership);
    session.client.state.removeListener(_checkMembership);
    _pushes.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(leave());
    super.dispose();
  }
}
