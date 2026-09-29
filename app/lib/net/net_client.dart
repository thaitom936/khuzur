/// WebSocket JSON client for the khuzur server.
///
/// Wire protocol (see server/service/ws_agent.lua):
///   request:  {seq, cmd, ...args}
///   response: {seq, cmd, err?, ...data}
///   push:     `{push: "<name>", ...data}`
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnState { offline, connecting, online }

class NetException implements Exception {
  final String code;

  NetException(this.code);

  @override
  String toString() => 'NetException($code)';
}

class NetClient {
  static const callTimeout = Duration(seconds: 10);
  static const pingInterval = Duration(seconds: 20);

  final ValueNotifier<ConnState> state = ValueNotifier(ConnState.offline);

  final _pushes = StreamController<Map<String, dynamic>>.broadcast();

  /// Server pushes (messages with a "push" field).
  Stream<Map<String, dynamic>> get pushes => _pushes.stream;

  /// Called after every (re)connect; used by the session to re-login.
  Future<void> Function()? onConnected;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  int _seq = 0;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  String? _url;
  bool _closed = false;
  int _retries = 0;

  Future<void> connect(String url) async {
    _url = url;
    _closed = false;
    await _open();
  }

  Future<void> _open() async {
    state.value = ConnState.connecting;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(_url!));
      await channel.ready;
      _channel = channel;
      _sub = channel.stream.listen(_onData,
          onDone: _onDisconnected, onError: (_) => _onDisconnected());
      _retries = 0;
      _pingTimer = Timer.periodic(pingInterval, (_) {
        call('ping', {'t': DateTime.now().millisecondsSinceEpoch})
            .catchError((_) => <String, dynamic>{});
      });
      await onConnected?.call();
      // Enable actions only once session authentication has succeeded.
      if (!_closed && identical(_channel, channel)) {
        state.value = ConnState.online;
      }
    } catch (_) {
      _onDisconnected();
    }
  }

  void _onData(dynamic raw) {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    final seq = msg['seq'];
    if (seq is int && _pending.containsKey(seq)) {
      _pending.remove(seq)!.complete(msg);
    } else if (msg['push'] is String) {
      _pushes.add(msg);
    }
  }

  void _onDisconnected() {
    _pingTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    _channel = null;
    for (final c in _pending.values) {
      c.completeError(NetException('disconnected'));
    }
    _pending.clear();
    if (_closed) {
      state.value = ConnState.offline;
      return;
    }
    state.value = ConnState.connecting;
    final delay = Duration(seconds: [1, 2, 5, 10][_retries.clamp(0, 3)]);
    _retries++;
    Timer(delay, () {
      if (!_closed) _open();
    });
  }

  /// Sends a request and completes with the response map. Throws
  /// [NetException] with the server's error code on `err` responses.
  Future<Map<String, dynamic>> call(String cmd,
      [Map<String, dynamic>? args]) async {
    final channel = _channel;
    if (channel == null) throw NetException('offline');
    final seq = ++_seq;
    final completer = Completer<Map<String, dynamic>>();
    _pending[seq] = completer;
    channel.sink.add(jsonEncode({'seq': seq, 'cmd': cmd, ...?args}));
    final resp = await completer.future.timeout(callTimeout, onTimeout: () {
      _pending.remove(seq);
      throw NetException('timeout');
    });
    final err = resp['err'];
    if (err is String) throw NetException(err);
    return resp;
  }

  void close() {
    _closed = true;
    _pingTimer?.cancel();
    _channel?.sink.close();
    state.value = ConnState.offline;
  }
}
