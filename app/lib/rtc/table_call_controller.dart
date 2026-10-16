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
  Timer? _renewal, _levels, _heartbeat, _retry;
  Future<void>? _pending, _leaveFuture;
  int _generation = 0;
  bool _disposed = false;
  String? _room;
  bool _foreground = true, _syncing = false, _scheduled = false;
  int _cameraEpoch = 0;
  bool speakerMuted = false;

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
      if (msg['push'] == 'rtc_balance' && msg['coins'] is int) {
        session.updateCoins(msg['coins'] as int);
        _notify();
      }
    });
    WidgetsBinding.instance.addObserver(this);
    _checkMembership();
  }

  bool get available =>
      supported &&
      session.loggedIn &&
      !game.spectating &&
      !game.gameOver &&
      game.roomCode != null &&
      game.humanSeat < game.seats.length &&
      !game.seats[game.humanSeat].bot;

  bool videoOn(int? uid) =>
      connected &&
      uid != null &&
      (uid == grant?.uid ? cameraOn : videos.contains(uid));

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
    // Game pushes can arrive during build. Reconcile in the next microtask.
    if (_scheduled || _disposed) return;
    _scheduled = true;
    scheduleMicrotask(() async {
      _scheduled = false;
      if (_disposed) return;
      if (!available ||
          !_foreground ||
          ((transport != null || busy) && game.roomCode != _room)) {
        if (transport != null || busy) await leave();
        return;
      }
      if (busy || closing) return;
      if (connected && cameraOn && _cameraEpoch != game.rtcVideoEpoch) {
        await _run((generation) async {
          await transport!.camera(false);
          if (!_current(generation)) return;
          cameraOn = false;
          final blocked = game.rtc['blocked'] as String?;
          if (blocked != null && blocked.isNotEmpty) error = blocked;
          await _report(generation);
        });
      } else if (!connected && game.rtcEnabled && _retry == null) {
        await join();
      }
      _notify();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      unawaited(leave());
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _checkMembership();
    }
  }

  void _retryLater() {
    if (_disposed || _retry != null || !game.rtcEnabled) return;
    _retry = Timer(const Duration(seconds: 5), () {
      _retry = null;
      _checkMembership();
    });
  }

  Future<Map<String, dynamic>> _control(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    final response = await session.client.call('rtc_control', {
      'code': _room ?? game.roomCode,
      'action': action,
      ...args,
    });
    final state = response['rtc'];
    if (!_disposed && game.roomCode == _room && state is Map) {
      game.updateRtc(Map<String, dynamic>.from(state));
    }
    return response;
  }

  Future<void> _report(int generation) async {
    if (!_current(generation) || !connected) return;
    await _control('state', {
      'joined': true,
      'camera': cameraOn,
      'microphone': microphoneOn,
      'video_epoch': _cameraEpoch,
    });
  }

  Future<void> _pulse() async {
    if (_syncing || busy || closing || !connected) return;
    _syncing = true;
    final generation = _generation;
    try {
      await _report(generation);
    } catch (e) {
      if (_current(generation)) {
        if (e is NetException &&
            const {
              'rtc_insufficient',
              'rtc_payment_required',
              'rtc_payer_offline',
              'rtc_payer_left',
              'rtc_billing_failed',
            }.contains(e.code)) {
          await _run((g) async {
            await transport!.camera(false);
            if (!_current(g)) return;
            cameraOn = false;
            error = e.code;
            await _report(g);
          });
          return;
        }
        error = 'rtc_failed';
        _retryLater();
        unawaited(leave());
      }
    } finally {
      _syncing = false;
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
          if (e is NetException &&
              const {
                'rtc_insufficient',
                'rtc_payment_required',
                'rtc_payer_offline',
                'rtc_payer_left',
                'rtc_billing_failed',
              }.contains(e.code)) {
            try {
              await transport?.camera(false);
              if (_current(generation)) cameraOn = false;
            } catch (_) {
              unawaited(leave());
            }
            return;
          }
          _retryLater();
          // A partially successful device operation must never keep capturing.
          unawaited(leave());
        }
      } finally {
        _pending = null;
        busy = false;
        _notify();
        _checkMembership();
      }
    }();
    _pending = operation;
    return operation;
  }

  Future<void> join() => _run(_join);

  Future<void> _join(int generation) async {
    if (!available || !_foreground || connected) return;
    _room = game.roomCode;
    onCallActive?.call(true);
    final response = await session.client.call('rtc_token', {'code': _room});
    if (!_current(generation)) return;
    final next = CallGrant.fromJson(response);
    final driver = transport ??= createTransport();
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
      _retryLater();
      unawaited(leave());
    };
    await driver.connect(next);
    if (!_current(generation)) return;
    connected = true;
    _scheduleRenewal(next);
    // No device capture on automatic entry. Presence starts only after SDK join.
    if (game.rtcEnabled) await _report(generation);
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) => _pulse());
    _levels = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _notify(),
    );
  }

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

  Future<void> toggleDevice({required bool camera, bool consent = false}) =>
      _run((generation) async {
        if (!available || !_foreground) return;
        _room = game.roomCode;
        final enable = !(camera ? cameraOn : microphoneOn);
        final driver = transport ??= createTransport();
        if (enable && !await driver.permission(camera: camera)) {
          if (_current(generation)) {
            error = camera ? 'rtc_camera_permission' : 'rtc_mic_permission';
          }
          return;
        }
        if (!_current(generation)) return;
        if (!connected) {
          await _control('start');
          if (!_current(generation)) return;
          await _join(generation);
        }
        if (!_current(generation) || !connected) return;
        if (camera && enable) {
          try {
            await _control('prepare', {'consent': consent});
          } on NetException catch (e) {
            error = e.code;
            return;
          }
          if (!_current(generation)) return;
          _cameraEpoch = game.rtcVideoEpoch;
        }
        if (camera) {
          await driver.camera(enable);
          if (_current(generation)) cameraOn = enable;
        } else {
          await driver.microphone(enable);
          if (_current(generation)) microphoneOn = enable;
        }
        if (_current(generation)) await _report(generation);
      });

  Future<void> toggleSpeaker() => _run((generation) async {
    if (!connected) return;
    final value = !speakerMuted;
    await transport!.muteAll(value);
    if (_current(generation)) speakerMuted = value;
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
    transport?.cancelPending();
    connected = microphoneOn = cameraOn = false;
    reconnecting = weakNetwork = speakerMuted = false;
    videos.clear();
    muted.clear();
    _speaking.clear();
    _renewal?.cancel();
    _levels?.cancel();
    _heartbeat?.cancel();
    _notify();
    final pending = _pending;
    final leavingRoom = _room;
    return _leaveFuture = () async {
      await pending;
      final driver = transport;
      final wasJoined = grant != null;
      transport = null;
      grant = null;
      try {
        await driver?.close();
        if (wasJoined && session.loggedIn && leavingRoom != null) {
          try {
            await session.client.call('rtc_control', {
              'code': leavingRoom,
              'action': 'state',
              'joined': false,
              'camera': false,
              'microphone': false,
            });
          } catch (_) {
            /* Socket/seat may already be gone. */
          }
        }
      } catch (_) {
        error ??= 'rtc_failed';
      } finally {
        closing = false;
        onCallActive?.call(false);
        _notify();
        _checkMembership();
      }
    }();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    game.removeListener(_checkMembership);
    session.client.state.removeListener(_checkMembership);
    _pushes.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(leave());
    super.dispose();
  }
}
