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
import '../style/player_avatar.dart';
import 'lobby_widgets.dart';

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
  List<LobbyRoom> _rooms = [];
  RoomFilter _filter = RoomFilter.all;
  bool _loadingRooms = false;
  bool _loadedRooms = false;
  bool _busy = false;
  bool _connecting = false;
  String? _roomsError;
  Timer? _refreshTimer;
  Session? _session;
  bool _wasOnline = false;
  int? _queueWaiting;
  int? _queueNeed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _session = context.read<Session>();
      _game = context.read<RemoteGameController>();
      if (_game!.gameOver) _game!.reset();
      _game!.addListener(_onGame);
      _pushSub = _session!.client.pushes.listen(_onPush);
      _session!.addListener(_onSessionChanged);
      _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted &&
            ModalRoute.of(context)?.isCurrent == true &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed &&
            _state == _LobbyState.lobby &&
            _session!.loggedIn) {
          _loadRooms();
        }
      });
      _connect();
    });
  }

  void _onSessionChanged() {
    final online = _session!.loggedIn;
    if (online && !_wasOnline) {
      _error = null;
      _loadRooms();
    }
    _wasOnline = online;
  }

  Future<void> _connect() async {
    if (_connecting || !mounted) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    final session = context.read<Session>();
    try {
      await session.ensureOnline();
      await session.refreshCoins();
      await _loadRooms();
    } on NetException catch (e) {
      if (mounted) setState(() => _error = e.code);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _loadRooms() async {
    if (!mounted || _loadingRooms || !_session!.loggedIn) return;
    setState(() {
      _loadingRooms = true;
    });
    try {
      final resp = await context.read<Session>().client.call('room_list');
      if (!mounted) return;
      final rooms = (resp['rooms'] as List? ?? [])
          .map((data) => LobbyRoom(data as Map<String, dynamic>))
          .toList();
      rooms.sort((a, b) {
        if (a.canSit != b.canSit) return a.canSit ? -1 : 1;
        if (a.started != b.started) return a.started ? 1 : -1;
        return a.code.compareTo(b.code);
      });
      setState(() {
        _rooms = rooms;
        _roomsError = null;
        _loadedRooms = true;
      });
    } on NetException catch (e) {
      if (mounted) setState(() => _roomsError = e.code);
    } finally {
      if (mounted) setState(() => _loadingRooms = false);
    }
  }

  void _watchRoom(String code) => _run(() async {
    if (_game!.roomCode != null && !_game!.spectating && !_game!.gameOver) {
      throw NetException('already_in_room');
    }
    if (_game!.gameOver) _game!.reset();
    _game!.suspended = false;
    await context.read<Session>().client.call('watch', {'code': code});
    // The snapshot push navigates to the table via _onGame.
  });

  void _onPush(Map<String, dynamic> msg) {
    if (!mounted) return;
    if (msg['push'] == 'invite') {
      _inviteDialog(msg);
    } else if (msg['push'] == 'queue_update') {
      setState(() {
        _queueWaiting = msg['waiting'] as int?;
        _queueNeed = msg['need'] as int?;
      });
    }
  }

  void _onGame() {
    final game = _game!;
    if (!mounted) return;
    if ((game.started || game.spectating) &&
        game.roomCode != null &&
        game.seats.isNotEmpty) {
      GoRouter.of(context).go('/online/table');
    } else if (game.roomCode != null && !game.started) {
      setState(() => _state = _LobbyState.waitingRoom);
    } else {
      setState(() {
        if (_state != _LobbyState.queueing) _state = _LobbyState.lobby;
      });
    }
  }

  @override
  void dispose() {
    _game?.removeListener(_onGame);
    _pushSub?.cancel();
    _session?.removeListener(_onSessionChanged);
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() body) async {
    if (_busy || !mounted) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await body();
    } on NetException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.code;
          _state = _LobbyState.lobby;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setLobbyState(_LobbyState s) {
    if (mounted) setState(() => _state = s);
    if (s == _LobbyState.lobby) _loadRooms();
  }

  void _cancelMatch() => _run(() async {
    final session = context.read<Session>();
    await session.client.call('cancel_match');
    await session.refreshCoins();
    _setLobbyState(_LobbyState.lobby);
  });

  void _createRoom(int size, int stake, bool locked) => _run(() async {
    await context.read<Session>().client.call('create_room', {
      'size': size,
      'stake': stake,
      'locked': locked,
    });
    _setLobbyState(_LobbyState.waitingRoom);
  });

  void _joinRoom(String code) => _watchRoom(code);

  void _leaveRoom() => _run(() async {
    final session = context.read<Session>();
    await session.client.call('leave_room');
    await session.refreshCoins();
    _setLobbyState(_LobbyState.lobby);
  });

  void _startRoom() => _run(() async {
    await context.read<Session>().client.call('start_room');
  });

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final l = L.of(context);
    final inLobby = _state == _LobbyState.lobby;
    final body = switch (_state) {
      _LobbyState.lobby => _lobbyView(session, l),
      _LobbyState.queueing => _queueView(l),
      _LobbyState.waitingRoom => _waitingRoomView(l),
    };
    return Scaffold(
      backgroundColor: lobbyBackground,
      appBar: AppBar(
        backgroundColor: lobbyGreen,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        toolbarHeight: 68,
        title: Row(
          children: [
            const Icon(Icons.style_outlined, size: 25),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MUUSHIG',
                    style: TextStyle(
                      fontSize: 18,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    l(session.loggedIn ? 'connected' : 'reconnecting'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xffc3d8cd),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (session.user != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.toll_outlined,
                    size: 18,
                    color: Color(0xffe3c88d),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${session.user!.coins}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          IconButton(
            tooltip: l('dailyTitle'),
            onPressed: session.loggedIn && !_busy
                ? () => _dailySheet(session, l)
                : null,
            icon: const Icon(Icons.redeem_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(top: false, child: body),
      bottomNavigationBar: inLobby
          ? NavigationBar(
              selectedIndex: 0,
              backgroundColor: Colors.white,
              indicatorColor: const Color(0xffe4eee7),
              onDestinationSelected: _busy
                  ? null
                  : (index) async {
                      if (index == 2) {
                        _profileSheet(session, l);
                        return;
                      }
                      final path = switch (index) {
                        1 => '/online/replays',
                        _ => null,
                      };
                      if (path == null) return;
                      await GoRouter.of(context).push(path);
                      if (mounted) _loadRooms();
                    },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.grid_view_rounded),
                  label: l('lobby'),
                ),
                // Friends is hidden for now (feature parked).
                NavigationDestination(
                  enabled: session.loggedIn,
                  icon: const Icon(Icons.history),
                  label: l('replays'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.person_outline),
                  label: l('profile'),
                ),
              ],
            )
          : null,
    );
  }

  Widget _lobbyView(Session session, L l) {
    final rooms = _rooms.where((room) => room.matches(_filter)).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 760 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.4;
        final compact = constraints.maxHeight < 450;
        final columns = wide ? 2 : 1;
        final inset = constraints.maxWidth > 1160
            ? (constraints.maxWidth - 1120) / 2
            : 16.0;
        return RefreshIndicator(
          onRefresh: session.loggedIn ? _loadRooms : _connect,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(inset, compact ? 8 : 18, inset, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l('lobbyTitle'),
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    color: lobbyGreen,
                                    letterSpacing: -0.7,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                if (!compact)
                                  Text(
                                    l('lobbySubtitle'),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: lobbyMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: l('play'),
                            onPressed: _busy
                                ? null
                                : () => GoRouter.of(context).push('/play'),
                            icon: const Icon(
                              Icons.school_outlined,
                              color: lobbyGreen,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 4 : 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: session.loggedIn && !_busy
                                    ? () => _sizeDialog(l)
                                    : null,
                                icon: const Icon(Icons.add, size: 18),
                                label: Text(l('createRoom')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextButton.icon(
                                onPressed: session.loggedIn && !_busy
                                    ? () => _joinDialog(l)
                                    : null,
                                icon: const Icon(Icons.tag, size: 18),
                                label: Text(l('joinByCode')),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final filter in RoomFilter.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    l(switch (filter) {
                                      RoomFilter.all => 'allTables',
                                      RoomFilter.available => 'availableTables',
                                      RoomFilter.waiting => 'waitingStatus',
                                      RoomFilter.playing => 'playingStatus',
                                    }),
                                  ),
                                  selected: _filter == filter,
                                  onSelected: (_) =>
                                      setState(() => _filter = filter),
                                  showCheckmark: false,
                                  selectedColor: const Color(0xffdce9df),
                                  side: BorderSide.none,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${l('rooms')} · ${rooms.length}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: lobbyMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (_loadingRooms)
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  semanticsLabel: l('loadingRooms'),
                                ),
                              ),
                            )
                          else
                            IconButton(
                              tooltip: l('refresh'),
                              onPressed: session.loggedIn ? _loadRooms : null,
                              icon: const Icon(Icons.refresh, size: 20),
                            ),
                        ],
                      ),
                      if (!session.loggedIn)
                        LobbyNotice(
                          message: l(
                            _error == null ? 'connecting' : 'connectionFailed',
                          ),
                          action: _connecting ? null : l('retry'),
                          onAction: _connect,
                        ),
                      if (_error != null && session.loggedIn)
                        LobbyNotice(
                          message: l.error(_error!),
                          action: l('dismiss'),
                          onAction: () => setState(() => _error = null),
                        ),
                      if (_roomsError != null && session.loggedIn)
                        LobbyNotice(
                          message: l('roomsFailed'),
                          action: l('retry'),
                          onAction: _loadingRooms ? null : _loadRooms,
                        ),
                      if (_busy) const LinearProgressIndicator(minHeight: 2),
                    ],
                  ),
                ),
              ),
              if (rooms.isNotEmpty)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  sliver: SliverList.builder(
                    itemCount: (rooms.length / columns).ceil(),
                    itemBuilder: (context, row) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var col = 0; col < columns; col++) ...[
                            if (col > 0) const SizedBox(width: 14),
                            Expanded(
                              child: row * columns + col < rooms.length
                                  ? LobbyRoomCard(
                                      key: ValueKey(
                                        rooms[row * columns + col].code,
                                      ),
                                      room: rooms[row * columns + col],
                                      l: l,
                                      enabled: session.loggedIn && !_busy,
                                      onJoin: () => _watchRoom(
                                        rooms[row * columns + col].code,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              if (rooms.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(inset, 22, inset, 28),
                    child: Column(
                      children: [
                        Icon(
                          _loadingRooms || !_loadedRooms
                              ? Icons.style_outlined
                              : Icons.search_off,
                          size: 36,
                          color: lobbyMuted,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l(
                            !session.loggedIn
                                ? 'connectionHint'
                                : _loadingRooms
                                ? 'loadingRooms'
                                : _roomsError != null
                                ? 'roomsFailed'
                                : _filter == RoomFilter.all
                                ? 'noRooms'
                                : 'noMatchingRooms',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        if (_filter != RoomFilter.all && _loadedRooms)
                          TextButton(
                            onPressed: () =>
                                setState(() => _filter = RoomFilter.all),
                            child: Text(l('showAllRooms')),
                          )
                        else if (!session.loggedIn)
                          OutlinedButton.icon(
                            onPressed: () => GoRouter.of(context).push('/play'),
                            icon: const Icon(Icons.school_outlined),
                            label: Text(l('play')),
                          ),
                      ],
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Center(
                    child: TextButton.icon(
                      onPressed: session.loggedIn
                          ? () => GoRouter.of(context).push('/online/rank')
                          : null,
                      icon: const Icon(Icons.emoji_events_outlined, size: 18),
                      label: Text(l('leaderboard')),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _queueView(L l) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            l('searching') +
                (_queueWaiting != null ? ' ($_queueWaiting/$_queueNeed)' : ''),
          ),
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
          Text(
            '${game.locked ? '🔒 ' : ''}${l('roomCode')}: '
            '${game.roomCode ?? '…'}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
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

  void _profileSheet(Session session, L l) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: PlayerAvatar(name: session.user?.name ?? ''),
                  title: Text(session.user?.name ?? l('profile')),
                  subtitle: session.user == null
                      ? null
                      : Text(
                          'Lv${session.user!.level} · ${l('points')}: ${session.user!.rating}\n'
                          '${l('games')}: ${session.user!.games} · ${l('wins')}: ${session.user!.wins}',
                        ),
                  trailing: session.loggedIn
                      ? IconButton(
                          tooltip: l('yourName'),
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _renameDialog(session, l);
                          },
                        )
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(l('settings')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    GoRouter.of(context).push('/settings');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: Text(l('play')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    GoRouter.of(context).push('/play');
                  },
                ),
              ],
            ),
          ),
        ),
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
    var locked = false;
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(l('players')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var n = 2; n <= 5; n++)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        // Coin tables are off for now: stake is always 0.
                        _createRoom(n, 0, locked);
                      },
                      child: Text('$n'),
                    ),
                ],
              ),
              SwitchListTile(
                dense: true,
                title: Text(l('lockedRoom')),
                subtitle: Text(
                  l('lockedHint'),
                  style: const TextStyle(fontSize: 11),
                ),
                value: locked,
                onChanged: (v) => setDialog(() => locked = v),
              ),
            ],
          ),
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
        title: Text(l.fmt('inviteFrom', '${msg['from'] ?? '?'}')),
        content: Text(
          '${l('roomCode')}: ${msg['code']}'
          '${(msg['stake'] as int? ?? 0) > 0 ? '\n${l('stake')}: ${msg['stake']}' : ''}',
        ),
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
              final resp = await session.client.call(
                'daily_claim',
                task == null ? null : {'task': task},
              );
              session.updateCoins(resp['coins'] as int);
              daily = await session.client.call('daily');
              setSheet(() {});
            } on NetException {
              // Already claimed or not done; the sheet already shows why.
            }
          }

          final tasks = (daily['tasks'] as List? ?? [])
              .cast<Map<String, dynamic>>();
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    l('dailyTitle'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
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
                      '${t['progress']}/${t['goal']} · +${t['reward']}',
                    ),
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
                          session.client
                              .call('invite', {'uid': f['uid']})
                              .catchError((Object e) {
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
