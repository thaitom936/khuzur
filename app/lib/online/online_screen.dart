/// Online lobby: connect + guest login, rename, coins/daily rewards,
/// friends, quick match and friend rooms (with stakes), leaderboard.
/// Navigates to the table when a game starts.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../game/remote_game.dart';
import '../l10n/strings.dart';
import '../net/net_client.dart';
import '../net/session.dart';
import '../settings/settings.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';

const stakes = [0, 100, 500, 2000];

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
  StreamSubscription? _pushSub;
  List<Map<String, dynamic>> _rooms = [];

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
    _pushSub = session.client.pushes.listen(_onPush);
    try {
      await session.ensureOnline();
      await session.refreshCoins();
      await _loadRooms();
    } on NetException catch (e) {
      if (mounted) setState(() => _error = e.code);
    }
  }

  Future<void> _loadRooms() async {
    try {
      final resp = await context.read<Session>().client.call('room_list');
      if (!mounted) return;
      setState(() => _rooms =
          (resp['rooms'] as List? ?? []).cast<Map<String, dynamic>>());
    } on NetException {
      // The lobby still works without the list.
    }
  }

  void _watchRoom(String code) => _run(() async {
        await context.read<Session>().client.call('watch', {'code': code});
        // The snapshot push navigates to the table via _onGame.
      });

  void _onPush(Map<String, dynamic> msg) {
    if (msg['push'] == 'invite' && mounted) {
      _inviteDialog(msg);
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
    _pushSub?.cancel();
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

  void _quickMatch(int stake) => _run(() async {
        await context.read<Session>().client
            .call('quick_match', {'stake': stake});
        _setLobbyState(_LobbyState.queueing);
      });

  void _cancelMatch() => _run(() async {
        await context.read<Session>().client.call('cancel_match');
        await context.read<Session>().refreshCoins();
        _setLobbyState(_LobbyState.lobby);
      });

  void _createRoom(int size, int stake) => _run(() async {
        await context.read<Session>().client
            .call('create_room', {'size': size, 'stake': stake});
        _setLobbyState(_LobbyState.waitingRoom);
      });

  void _joinRoom(String code) => _run(() async {
        await context.read<Session>().client.call('join_room', {'code': code});
        _setLobbyState(_LobbyState.waitingRoom);
      });

  void _leaveRoom() => _run(() async {
        await context.read<Session>().client.call('leave_room');
        await context.read<Session>().refreshCoins();
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
            subtitle: Text(
                '${l('games')}: ${user.games} · ${l('wins')}: ${user.wins}\n'
                '${l('coins')}: ${user.coins}'),
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
          MyButton(
            onPressed: () => _stakeSheet(l, (stake) => _quickMatch(stake)),
            child: Text(l('quickMatch')),
          ),
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
            onPressed: () => _dailySheet(session, l),
            child: Text(l('dailyTitle')),
          ),
          const SizedBox(height: 12),
          MyButton(
            onPressed: () => GoRouter.of(context).push('/online/friends'),
            child: Text(l('friends')),
          ),
          const SizedBox(height: 12),
          _roomList(l),
          const SizedBox(height: 12),
          MyButton(
            onPressed: () => GoRouter.of(context).push('/online/replays'),
            child: Text(l('replays')),
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

  Widget _roomList(L l) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l('rooms'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: _loadRooms,
            ),
          ],
        ),
        if (_rooms.isEmpty)
          Text(l('noRooms'), style: const TextStyle(fontSize: 12))
        else
          for (final room in _rooms) _roomRow(l, room),
      ],
    );
  }

  Widget _roomRow(L l, Map<String, dynamic> room) {
    final code = room['code'] as String;
    final started = room['started'] == true;
    final stake = room['stake'] as int? ?? 0;
    final seated = room['seated'] as int? ?? 0;
    final size = room['size'] as int? ?? 0;
    final bots = room['bots'] as int? ?? 0;
    final names = (room['names'] as List? ?? []).join(' · ');
    // Sit on a free pre-start seat, or take over a bot in a free table.
    final canSit =
        started ? (bots > 0 && stake == 0) : (seated < size);

    return ListTile(
      dense: true,
      title: Text('#$code  $names'),
      subtitle: Text([
        '$seated/$size',
        if (stake > 0) '${l('stake')}: $stake',
        if (started) l.fmt('inProgress', room['round'] ?? ''),
        if ((room['watchers'] as int? ?? 0) > 0) '👁 ${room['watchers']}',
      ].join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canSit)
            TextButton(
              onPressed: () => _joinRoom(code),
              child: Text(l('sit')),
            ),
          if (started)
            TextButton(
              onPressed: () => _watchRoom(code),
              child: Text(l('watch')),
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
          if (game.stake > 0) Text('${l('stake')}: ${game.stake}'),
          const SizedBox(height: 12),
          for (final s in game.seats) Text(s.name),
          Text('${game.seats.length} / ${game.numPlayers}'),
          const SizedBox(height: 16),
          Text(l('waitingFriends')),
          const SizedBox(height: 16),
          MyButton(
            onPressed: () => _inviteSheet(l),
            child: Text(l('inviteFriends')),
          ),
          const SizedBox(height: 12),
          MyButton(onPressed: _startRoom, child: Text(l('startNow'))),
          const SizedBox(height: 12),
          MyButton(onPressed: _leaveRoom, child: Text(l('cancel'))),
        ],
      ),
    );
  }

  // ---- dialogs & sheets ----

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

  void _stakeSheet(L l, void Function(int stake) onPicked) {
    final coins = context.read<Session>().user?.coins ?? 0;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l('stake'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final stake in stakes)
              ListTile(
                enabled: stake <= coins,
                title: Text(stake == 0 ? l('casual') : '$stake'),
                leading: Icon(stake == 0 ? Icons.sports_esports : Icons.paid),
                onTap: () {
                  Navigator.pop(context);
                  onPicked(stake);
                },
              ),
          ],
        ),
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
                  _stakeSheet(l, (stake) => _createRoom(n, stake));
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

  void _inviteDialog(Map<String, dynamic> msg) {
    final l = L(context.read<SettingsController>().lang.value);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.fmt('inviteFrom', msg['from'] ?? '?')),
        content: Text('${l('roomCode')}: ${msg['code']}'
            '${(msg['stake'] as int? ?? 0) > 0 ? '\n${l('stake')}: ${msg['stake']}' : ''}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l('decline')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _joinRoom(msg['code'] as String);
            },
            child: Text(l('join')),
          ),
        ],
      ),
    );
  }

  Future<void> _dailySheet(Session session, L l) async {
    Map<String, dynamic> daily;
    try {
      daily = await session.client.call('daily');
    } on NetException catch (e) {
      setState(() => _error = e.code);
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          Future<void> claim([String? task]) async {
            try {
              final resp = await session.client
                  .call('daily_claim', task == null ? null : {'task': task});
              session.updateCoins(resp['coins'] as int);
              daily = await session.client.call('daily');
              setSheet(() {});
            } on NetException {
              // Already claimed or not done; the sheet already shows why.
            }
          }

          final tasks =
              (daily['tasks'] as List? ?? []).cast<Map<String, dynamic>>();
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(l('dailyTitle'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                ),
                ListTile(
                  title: Text(l('dailyBonus')),
                  subtitle: Text('+${daily['bonus']}'),
                  trailing: daily['bonus_claimed'] == true
                      ? Text(l('claimed'))
                      : FilledButton(
                          onPressed: () => claim(),
                          child: Text(l('claim')),
                        ),
                ),
                for (final t in tasks)
                  ListTile(
                    title: Text(l('task_${t['id']}')),
                    subtitle: Text(
                        '${t['progress']}/${t['goal']} · +${t['reward']}'),
                    trailing: t['claimed'] == true
                        ? Text(l('claimed'))
                        : FilledButton(
                            onPressed: t['progress'] == t['goal']
                                ? () => claim(t['id'] as String)
                                : null,
                            child: Text(l('claim')),
                          ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _inviteSheet(L l) async {
    final session = context.read<Session>();
    List<Map<String, dynamic>> friends;
    try {
      final resp = await session.client.call('friends');
      friends = (resp['friends'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .where((f) => f['online'] == true)
          .toList();
    } on NetException catch (e) {
      setState(() => _error = e.code);
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: friends.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.error('friend_offline')),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final f in friends)
                    ListTile(
                      title: Text(f['name'] as String),
                      trailing: TextButton(
                        onPressed: () {
                          session.client.call('invite',
                              {'uid': f['uid']}).catchError((Object e) {
                            return <String, dynamic>{};
                          });
                          Navigator.pop(context);
                        },
                        child: Text(l('invite')),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
