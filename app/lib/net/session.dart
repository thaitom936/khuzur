/// Online session: server address, device identity, login state.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'net_client.dart';

/// Dev default: the development server. Change in the settings screen.
const defaultServerUrl = 'ws://54.254.223.5:9601/ws';

class UserInfo {
  final int uid;
  String name;
  int games;
  int wins;

  UserInfo({
    required this.uid,
    required this.name,
    required this.games,
    required this.wins,
  });
}

class Session extends ChangeNotifier {
  final NetClient client = NetClient();

  UserInfo? user;
  String? _token;
  bool _connecting = false;

  /// Set when the server says we are (still) in a room: a snapshot push
  /// follows and the UI should go straight to the table.
  bool inRoom = false;

  Session() {
    client.onConnected = _loginOnConnect;
    client.state.addListener(notifyListeners);
  }

  bool get loggedIn => user != null && client.state.value == ConnState.online;

  Future<String> _serverUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('serverUrl') ?? defaultServerUrl;
  }

  Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverUrl', url);
    client.close();
    user = null;
    notifyListeners();
  }

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('deviceId');
    if (id == null) {
      final rng = Random.secure();
      id = List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
      await prefs.setString('deviceId', id);
    }
    return id;
  }

  /// Connects and logs in (guest). Safe to call repeatedly.
  Future<void> ensureOnline() async {
    if (loggedIn || _connecting) return;
    _connecting = true;
    try {
      await client.connect(await _serverUrl());
    } finally {
      _connecting = false;
    }
    if (user == null) throw NetException('login_failed');
  }

  /// Runs on every (re)connect: resume by token, else guest login.
  Future<void> _loginOnConnect() async {
    final prefs = await SharedPreferences.getInstance();
    _token ??= prefs.getString('token');

    Map<String, dynamic>? resp;
    if (_token != null) {
      try {
        resp = await client.call('resume', {'token': _token});
      } on NetException {
        resp = null; // expired token: fall through to guest login
      }
    }
    if (resp == null) {
      resp = await client.call('login', {
        'device': await _deviceId(),
        'lang': prefs.getString('lang') ?? 'en',
      });
      _token = resp['token'] as String?;
      if (_token != null) await prefs.setString('token', _token!);
    }
    user = UserInfo(
      uid: resp['uid'] as int,
      name: resp['name'] as String,
      games: resp['games'] as int? ?? 0,
      wins: resp['wins'] as int? ?? 0,
    );
    inRoom = resp['in_room'] == true;
    notifyListeners();
  }

  Future<void> setName(String name) async {
    final resp = await client.call('set_name', {'name': name});
    user?.name = resp['name'] as String;
    notifyListeners();
  }

  Future<void> setLang(String lang) async {
    if (loggedIn) {
      try {
        await client.call('set_lang', {'lang': lang});
      } on NetException {
        // Not fatal; the preference is stored locally regardless.
      }
    }
  }
}
