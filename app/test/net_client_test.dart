import 'dart:async';
import 'dart:io';

import 'package:card/net/net_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connection enables actions only after authentication completes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    server.listen((request) async {
      sockets.add(await WebSocketTransformer.upgrade(request));
    });
    final client = NetClient();
    final entered = Completer<void>();
    final authenticated = Completer<void>();
    client.onConnected = () async {
      entered.complete();
      await authenticated.future;
    };
    addTearDown(() async {
      client.close();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });
    final connection = client.connect('ws://127.0.0.1:${server.port}');
    await entered.future.timeout(const Duration(seconds: 5));
    expect(client.state.value, ConnState.connecting);
    authenticated.complete();
    await connection;
    expect(client.state.value, ConnState.online);
  });
}
