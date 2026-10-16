import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../net/net_client.dart';

String chatNonce() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class ChatController extends ChangeNotifier {
  ChatController(this.client, this.channel) {
    _sub = client.pushes.listen(_push);
    client.state.addListener(_connection);
  }
  final NetClient client;
  final String channel;
  late final StreamSubscription<Map<String, dynamic>> _sub;
  final List<Map<String, dynamic>> messages = [];
  final Map<String, Map<String, dynamic>> pending = {};
  Map<String, dynamic> capabilities = {};
  bool loading = true, olderAvailable = false, closed = false, disposed = false;
  String? error;
  bool get mediaAllowed => capabilities['media'] == true;
  bool get moderator => capabilities['moderator'] == true;
  bool get writable =>
      client.state.value == ConnState.online &&
      capabilities['write'] == true &&
      error == null &&
      !closed &&
      !loading;
  void merge(Iterable<dynamic> incoming) {
    for (final raw in incoming) {
      final row = Map<String, dynamic>.from(raw as Map);
      final i = messages.indexWhere((m) => m['id'] == row['id']);
      if (i < 0) {
        messages.add(row);
      } else {
        messages[i] = row;
      }
      final optimistic = pending[row['nonce']];
      if (optimistic != null && optimistic['uid'] == row['uid']) {
        pending.remove(row['nonce']);
      }
    }
    messages.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
  }

  Future<void> open({bool reconnect = false}) async {
    if (disposed || closed) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      int? cursor = reconnect && messages.isNotEmpty
          ? messages.last['id'] as int
          : null;
      var first = true;
      do {
        final response = await client.call(
          first ? 'chat_open' : 'chat_history',
          {'channel': channel, 'after': ?cursor},
        );
        if (disposed) return;
        if (response['capabilities'] is Map) {
          capabilities = Map<String, dynamic>.from(
            response['capabilities'] as Map,
          );
        }
        final rows = response['messages'] as List? ?? [];
        merge(rows);
        if (cursor == null) {
          olderAvailable = response['has_more'] == true;
          break;
        }
        if (rows.isEmpty || response['has_more'] != true) break;
        cursor = rows.last['id'] as int;
        first = false;
      } while (!disposed);
    } catch (e) {
      if (!disposed) error = e is NetException ? e.code : 'generic';
    }
    if (!disposed) {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> older() async {
    if (loading || messages.isEmpty || !olderAvailable) return;
    loading = true;
    notifyListeners();
    try {
      final response = await client.call('chat_history', {
        'channel': channel,
        'before': messages.first['id'],
      });
      if (disposed) return;
      merge(response['messages'] as List? ?? []);
      olderAvailable = response['has_more'] == true;
    } catch (e) {
      if (!disposed) error = e is NetException ? e.code : 'generic';
    }
    if (!disposed) {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> send(
    String body, {
    String? mediaId,
    int? uid,
    String? nonce,
  }) async {
    if (!writable) return;
    nonce ??= chatNonce();
    pending[nonce] = {
      'nonce': nonce,
      'body': body,
      'media_id': mediaId,
      'uid': uid,
      'state': 'sending',
    };
    notifyListeners();
    try {
      final response = await client.call('chat_send', {
        'channel': channel,
        'nonce': nonce,
        'body': body,
        'media_id': ?mediaId,
      });
      if (disposed) return;
      merge([response['message']]);
      pending.remove(nonce);
    } catch (e) {
      if (disposed) return;
      if (pending.containsKey(nonce)) {
        pending[nonce]!['state'] = 'failed';
        pending[nonce]!['error'] = e is NetException ? e.code : 'generic';
      }
    }
    if (!disposed) notifyListeners();
  }

  Future<void> action(String cmd, Map<String, dynamic> args) async {
    await client.call(cmd, {'channel': channel, ...args});
  }

  void _push(Map<String, dynamic> event) {
    if (disposed || event['channel'] != channel) return;
    switch (event['push']) {
      case 'chat_message':
        merge([event['message']]);
      case 'chat_deleted':
        for (final m in messages) {
          if (m['id'] == event['id']) {
            m['deleted'] = true;
            m['body'] = '';
            m.remove('media');
          }
        }
      case 'chat_closed':
        closed = true;
      default:
        return;
    }
    notifyListeners();
  }

  void _connection() {
    if (client.state.value == ConnState.online && !closed) {
      unawaited(open(reconnect: true));
    } else if (!disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    disposed = true;
    _sub.cancel();
    client.state.removeListener(_connection);
    client
        .call('chat_close', {'channel': channel})
        .catchError((_) => <String, dynamic>{});
    super.dispose();
  }
}
