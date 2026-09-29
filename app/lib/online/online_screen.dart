/// Online lobby: connect + guest login, rename, quick match, friend rooms,
/// leaderboard entry. Navigates to the table when a game starts.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../game/remote_game.dart';
import '../l10n/strings.dart';
import '../net/net_client.dart';
import '../net/session.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';

class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

enum _LobbyState { lobby, queueing, waitingRoom }

class _OnlineScreenState extends State<OnlineScreen> {
  _LobbyState _state = _LobbyState.lobby;
  String? _error;
  RemoteGameController? _game;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  Future<void> _connect() async {
    final session = context.read<Session>();
    // Instantiating the controller here makes sure it is subscribed to
    // pushes before any game can start.
    _game = context.read<RemoteGameController>();
    if (_game!.gameOver) _game!.reset();
    _game!.addListener(_onGame);
    try {
      await session.ensureOnline();
    } on NetException catch (e) {
      if (mounted) setState(() => _error = e.code);
    }
  }

  void _onGame() {
    final game = _game!;
    if (!mounted) return;
    if (game.started && game.seats.isNotEmpty && !game.suspended) {
      GoRouter.of(context).go('/online/table');
    } else if (game.roomCode != null && !game.started) {
      setState(() => _state = _LobbyState.waitingRoom);
    } else {
      setState(() {}); // e.g. a suspended game just ended
    }
  }

  @override
  void dispose() {
    _game?.removeListener(_onGame);
    super.dispose();
  }

  Future<void> _run(Future<void> Function() body) async {
    setState(() => _error = null);
    try {
      await body();
    } on NetException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.code;
          _state = _LobbyState.lobby;
        });
      }
    }
  }

  void _setLobbyState(_LobbyState s) {
    if (mounted) setState(() => _state = s);
  }

  void _quickMatch() => _run(() async {
        await context.read<Session>().client.call('quick_match');
        _setLobbyState(_LobbyState.queueing);
      });

  void _cancelMatch() => _run(() async {
        await context.read<Session>().client.call('cancel_match');
        _setLobbyState(_LobbyState.lobby);
      });

  void _createRoom(int size) => _run(() async {
        await context.read<Session>().client
            .call('create_room', {'size': size});
        _setLobbyState(_LobbyState.waitingRoom);
      });

  void _joinRoom(String code) => _run(() async {
        await context.read<Session>().client.call('join_room', {'code': code});
        _setLobbyState(_LobbyState.waitingRoom);
      });

  void _leaveRoom() => _run(() async {
        await context.read<Session>().client.call('leave_room');
        _setLobbyState(_LobbyState.lobby);
      });

  void _startRoom() => _run(() async {
        await context.read<Session>().client.call('start_room');
      });

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();
    final session = context.watch<Session>();
    final l = L.of(context);

    final Widget body;
    if (!session.loggedIn) {
      body = _connectingView(session, l);
    } else {
      body = switch (_state) {
        _LobbyState.lobby => _lobbyView(session, l),
        _LobbyState.queueing => _queueView(l),
        _LobbyState.waitingRoom => _waitingRoomView(l),
      };
    }

    return Scaffold(
      backgroundColor: palette.backgroundMain,
      body: ResponsiveScreen(
        squarishMainArea: body,
        rectangularMenuArea: MyButton(
          onPressed: () {
            if (_state == _LobbyState.waitingRoom) _leaveRoom();
            GoRouter.of(context).go('/');
          },
          child: Text(l('back')),
        ),
      ),
    );
  }

  Widget _connectingView(Session session, L l) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(_error != null ? l.error(_error!) : l('connecting')),
          if (_error != null)
            TextButton(onPressed: _connect, child: const Text('↻')),
        ],
      ),
    );
  }

  Widget _lobbyView(Session session, L l) {
    final user = session.user!;
    return SingleChildScrollView(
      child: Column(
        children: [
          ListTile(
            title: Text(user.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle:
                Text('${l('games')}: ${user.games} · ${l('wins')}: ${user.wins}'),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _renameDialog(session, l),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(l.error(_error!),
                  style: const TextStyle(color: Colors.red)),
            ),
          if (_game != null && _game!.started && _game!.suspended) ...[
            const SizedBox(height: 12),
            MyButton(
              onPressed: () {
                _game!.suspended = false;
                GoRouter.of(context).go('/online/table');
              },
              child: Text(l('resumeGame')),
            ),
          ],
          const SizedBox(height: 12),
          MyButton(onPressed: _quickMatch, child: Text(l('quickMatch'))),
          const SizedBox(height: 12),
          MyButton(
            onPressed: () => _sizeDialog(l),
            child: Text(l('createRoom')),
          ),
          const SizedBox(height: 12),
          MyButton(
            onPressed: () => _joinDialog(l),
            child: Text(l('joinRoom')),
          ),
          const SizedBox(height: 12),
          MyButton(
            onPressed: () => GoRouter.of(context).push('/online/rank'),
            child: Text(l('leaderboard')),
          ),
        ],
      ),
    );
  }

  Widget _queueView(L l) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(l('searching')),
          const SizedBox(height: 16),
          MyButton(onPressed: _cancelMatch, child: Text(l('cancel'))),
        ],
      ),
    );
  }

  Widget _waitingRoomView(L l) {
    final game = _game!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${l('roomCode')}: ${game.roomCode ?? '…'}',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          for (final s in game.seats) Text(s.name),
          Text('${game.seats.length} / ${game.numPlayers}'),
          const SizedBox(height: 16),
          Text(l('waitingFriends')),
          const SizedBox(height: 16),
          MyButton(onPressed: _startRoom, child: Text(l('startNow'))),
          const SizedBox(height: 12),
          MyButton(onPressed: _leaveRoom, child: Text(l('cancel'))),
        ],
      ),
    );
  }

  void _renameDialog(Session session, L l) {
    final controller = TextEditingController(text: session.user!.name);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l('yourName')),
        content: TextField(controller: controller, maxLength: 24),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l('cancel')),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                _run(() => session.setName(name));
              }
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _sizeDialog(L l) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l('players')),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var n = 2; n <= 5; n++)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _createRoom(n);
                },
                child: Text('$n'),
              ),
          ],
        ),
      ),
    );
  }

  void _joinDialog(L l) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l('roomCode')),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _joinRoom(controller.text.trim());
            },
            child: Text(l('join')),
          ),
        ],
      ),
    );
  }
}
