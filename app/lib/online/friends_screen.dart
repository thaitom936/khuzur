/// Friends: list with online status, incoming requests, add by name/ID.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../net/net_client.dart';
import '../net/session.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _requests = [];
  final _addController = TextEditingController();
  String? _notice;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = context.read<Session>().client.pushes.listen((msg) {
      if (msg['push'] == 'friend_update') _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _addController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final resp = await context.read<Session>().client.call('friends');
      if (!mounted) return;
      setState(() {
        _friends = (resp['friends'] as List? ?? []).cast<Map<String, dynamic>>();
        _requests =
            (resp['requests'] as List? ?? []).cast<Map<String, dynamic>>();
      });
    } on NetException catch (e) {
      if (mounted) setState(() => _notice = e.code);
    }
  }

  Future<void> _add() async {
    final q = _addController.text.trim();
    if (q.isEmpty) return;
    try {
      final resp =
          await context.read<Session>().client.call('friend_add', {'q': q});
      if (!mounted) return;
      _addController.clear();
      setState(() => _notice =
          resp['status'] == 'accepted' ? 'accepted' : 'requestSent');
      _load();
    } on NetException catch (e) {
      if (mounted) setState(() => _notice = e.code);
    }
  }

  Future<void> _respond(int uid, bool accept) async {
    try {
      await context.read<Session>().client
          .call('friend_respond', {'uid': uid, 'accept': accept});
    } on NetException {
      // e.g. the request was withdrawn; the reload below shows the truth.
    }
    _load();
  }

  Future<void> _watch(int uid) async {
    try {
      await context.read<Session>().client.call('watch', {'uid': uid});
      // The snapshot push flips the game controller to "started"; the
      // lobby below this screen navigates to the table automatically.
      if (mounted) GoRouter.of(context).pop();
    } on NetException catch (e) {
      if (mounted) setState(() => _notice = e.code);
    }
  }

  Future<void> _remove(int uid) async {
    try {
      await context.read<Session>().client.call('friend_remove', {'uid': uid});
    } on NetException {
      // Ignore: the reload shows the current state.
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();
    final l = L.of(context);

    String noticeText(String code) => switch (code) {
          'requestSent' => l('requestSent'),
          'accepted' => l('friends'),
          _ => l.error(code),
        };

    return Scaffold(
      backgroundColor: palette.backgroundMain,
      body: ResponsiveScreen(
        squarishMainArea: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l('friends'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addController,
                      decoration: InputDecoration(hintText: l('addFriend')),
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _add, child: Text(l('add'))),
                ],
              ),
            ),
            if (_notice != null)
              Text(noticeText(_notice!), textAlign: TextAlign.center),
            Expanded(
              child: ListView(
                children: [
                  if (_requests.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(l('requests'),
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  for (final r in _requests)
                    ListTile(
                      dense: true,
                      title: Text('${r['name']} (${r['uid']})'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _respond(r['uid'] as int, true),
                            child: Text(l('accept')),
                          ),
                          TextButton(
                            onPressed: () => _respond(r['uid'] as int, false),
                            child: Text(l('decline')),
                          ),
                        ],
                      ),
                    ),
                  for (final f in _friends)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.circle,
                        size: 12,
                        color: f['online'] == true ? Colors.green : Colors.grey,
                      ),
                      title: Text('${f['name']} (${f['uid']})'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (f['in_room'] == true)
                            TextButton(
                              onPressed: () => _watch(f['uid'] as int),
                              child: Text(l('watch')),
                            ),
                          IconButton(
                            icon: const Icon(Icons.person_remove, size: 18),
                            onPressed: () => _remove(f['uid'] as int),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        rectangularMenuArea: MyButton(
          onPressed: () => GoRouter.of(context).pop(),
          child: Text(l('back')),
        ),
      ),
    );
  }
}
