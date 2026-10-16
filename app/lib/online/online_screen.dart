/// Online lobby: connect + guest login, rename, coins/daily rewards,
/// friends, quick match and friend rooms (with stakes), leaderboard.
/// Navigates to the table when a game starts.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../chat/chat_screen.dart';
import '../game/remote_game.dart';
import '../l10n/strings.dart';
import '../net/net_client.dart';
import '../net/session.dart';
import '../settings/settings.dart';
import '../style/lobby_input_dialog.dart';
import '../style/lobby_theme.dart';
import '../style/my_button.dart';
import '../style/player_avatar.dart';
import 'lobby_widgets.dart';

class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

enum _LobbyState { lobby, queueing }

class _OnlineScreenState extends State<OnlineScreen> {
  _LobbyState _state = _LobbyState.lobby;
  String? _error;
  RemoteGameController? _game;
  StreamSubscription? _pushSub;
  List<LobbyRoom> _rooms = [];
  String _filter = 'all';
  int _tab = 0;
  final _visitedTabs = <int>{0};
  final _roomScroll = ScrollController();
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
    if (game.roomCode != null && game.seats.isNotEmpty) {
      GoRouter.of(context).go('/online/table');
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
    _roomScroll.dispose();
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

  void _createRoom(
    int size,
    int stake,
    bool locked, [
    String gameType = 'muushig',
    int deckSize = 36,
    bool transfer = false,
    bool allowDraw = true,
  ]) => _run(() async {
    await context.read<Session>().client.call('create_room', {
      'size': size,
      'stake': stake,
      'locked': locked,
      'game_type': gameType,
      if (gameType == 'durak') 'deck_size': deckSize,
      if (gameType == 'durak') 'transfer': transfer,
      if (gameType == 'durak') 'allow_draw': allowDraw,
    });
  });

  void _joinRoom(String code) => _watchRoom(code);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final l = L.of(context);
    final inLobby = _state == _LobbyState.lobby;
    final lang = ['en', 'mn', 'zh'].contains(l.lang) ? l.lang : 'en';
    final titles = [l('lobby'), l('chat'), l('profile')];
    return LobbyTheme(
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(inLobby ? titles[_tab] : l('roomCode')),
            actions: [
              if (inLobby && _tab == 0)
                IconButton(
                  tooltip: l('refresh'),
                  onPressed: session.loggedIn && !_loadingRooms
                      ? _loadRooms
                      : null,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              if (inLobby && _tab == 1)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Text(
                      langNames[lang]!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                if (!session.loggedIn)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: LobbyNotice(
                      message: l(
                        _error == null ? 'reconnecting' : 'connectionFailed',
                      ),
                      action: _connecting ? null : l('retry'),
                      onAction: _connect,
                    ),
                  ),
                if (_error != null && session.loggedIn)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: LobbyNotice(
                      message: l.error(_error!),
                      action: l('dismiss'),
                      onAction: () => setState(() => _error = null),
                    ),
                  ),
                Expanded(
                  child: switch (_state) {
                    _LobbyState.queueing => _queueView(l),
                    _LobbyState.lobby => IndexedStack(
                      index: _tab,
                      children: [
                        _lobbyView(session, l),
                        if (_visitedTabs.contains(1))
                          ChatScreen(
                            key: ValueKey('lobby-chat-$lang'),
                            channel: 'lobby:$lang',
                            title: l('chat'),
                            embedded: true,
                            active: _tab == 1,
                          )
                        else
                          const SizedBox.shrink(),
                        _profileView(session, l),
                      ],
                    ),
                  },
                ),
              ],
            ),
          ),
          bottomNavigationBar: inLobby
              ? NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (index) {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _tab = index;
                      _visitedTabs.add(index);
                    });
                    if (index == 0 && session.loggedIn) _loadRooms();
                  },
                  destinations: [
                    NavigationDestination(
                      icon: const Icon(Icons.grid_view_rounded),
                      label: l('lobby'),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: l('chat'),
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.person_outline),
                      label: l('profile'),
                    ),
                  ],
                )
              : null,
        ),
      ),
    );
  }

  Widget _lobbyView(Session session, L l) {
    final rooms = _rooms
        .where((room) => _filter == 'all' || room.gameType == _filter)
        .toList();
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= 760 &&
                      MediaQuery.textScalerOf(context).scale(1) < 1.4
                  ? 2
                  : 1;
              final inset = constraints.maxWidth > 1160
                  ? (constraints.maxWidth - 1120) / 2
                  : 16.0;
              return RefreshIndicator(
                onRefresh: session.loggedIn ? _loadRooms : _connect,
                child: CustomScrollView(
                  key: const PageStorageKey('lobby-rooms'),
                  controller: _roomScroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(inset, 0, inset, 16),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_game?.roomCode != null && !_game!.gameOver)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: FilledButton.tonalIcon(
                                  onPressed: () =>
                                      GoRouter.of(context).go('/online/table'),
                                  icon: const Icon(Icons.undo),
                                  label: Text(l('returnTable')),
                                ),
                              ),
                            Row(
                              spacing: 4,
                              children: [
                                for (final game in {
                                  'all': l('allTables'),
                                  'muushig': 'Muushig',
                                  'mongol13': 'Mongol 13',
                                  'durak': 'Durak',
                                  'thousand': 'Thousand',
                                }.entries)
                                  Expanded(
                                    child: Tooltip(
                                      message: game.value,
                                      child: ChoiceChip(
                                        key: ValueKey(
                                          'game-filter-${game.key}',
                                        ),
                                        padding: EdgeInsets.zero,
                                        labelPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 3,
                                            ),
                                        label: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            game.value,
                                            maxLines: 1,
                                            softWrap: false,
                                          ),
                                        ),
                                        selected: _filter == game.key,
                                        showCheckmark: false,
                                        labelStyle: TextStyle(
                                          fontSize: 12,
                                          color: _filter == game.key
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.onPrimary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                        ),
                                        onSelected: (_) {
                                          setState(() => _filter = game.key);
                                          if (_roomScroll.hasClients) {
                                            _roomScroll.jumpTo(0);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (_roomsError != null && session.loggedIn) ...[
                              const SizedBox(height: 12),
                              LobbyNotice(
                                message: l('roomsFailed'),
                                action: l('retry'),
                                onAction: _loadingRooms ? null : _loadRooms,
                              ),
                            ],
                            if (_busy)
                              const LinearProgressIndicator(minHeight: 2),
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
                          padding: EdgeInsets.fromLTRB(inset, 24, inset, 24),
                          child: Column(
                            children: [
                              if (session.loggedIn &&
                                  _loadingRooms &&
                                  !_loadedRooms)
                                const CircularProgressIndicator()
                              else
                                Icon(
                                  Icons.layers_outlined,
                                  size: 32,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              const SizedBox(height: 12),
                              Text(
                                l(
                                  !session.loggedIn
                                      ? 'connectionHint'
                                      : _loadingRooms && !_loadedRooms
                                      ? 'loadingRooms'
                                      : _roomsError != null
                                      ? 'roomsFailed'
                                      : _filter == 'all'
                                      ? 'noRooms'
                                      : 'noMatchingRooms',
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              if (_filter != 'all' && _loadedRooms)
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _filter = 'all'),
                                  child: Text(l('showAllRooms')),
                                )
                              else if (!session.loggedIn)
                                TextButton.icon(
                                  onPressed: () =>
                                      GoRouter.of(context).push('/play'),
                                  icon: const Icon(Icons.school_outlined),
                                  label: Text(l('play')),
                                ),
                            ],
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
              );
            },
          ),
        ),
        Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: session.loggedIn && !_busy
                        ? () => _sizeDialog(l)
                        : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l('createRoom')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
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
        ),
      ],
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

  // ---- dialogs & sheets ----

  Widget _profileView(Session session, L l) => ListView(
    key: const PageStorageKey('lobby-profile'),
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  PlayerAvatar(name: session.user?.name ?? '', size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      session.user?.name ?? l('profile'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l('yourName'),
                    onPressed: session.loggedIn
                        ? () => _renameDialog(session, l)
                        : null,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                ],
              ),
              const Divider(height: 32),
              Row(
                children: [
                  const Icon(Icons.toll_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l('coins'))),
                  Text(
                    '${session.user?.coins ?? 0}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: [
            _profileLink(
              Icons.history,
              l('replays'),
              session.loggedIn
                  ? () => GoRouter.of(context).push('/online/replays')
                  : null,
            ),
            _profileLink(
              Icons.redeem_outlined,
              l('dailyTitle'),
              session.loggedIn && !_busy ? () => _dailySheet(session, l) : null,
            ),
            _profileLink(
              Icons.emoji_events_outlined,
              l('leaderboard'),
              session.loggedIn
                  ? () => GoRouter.of(context).push('/online/rank')
                  : null,
            ),
            _profileLink(
              Icons.settings_outlined,
              l('settings'),
              () => GoRouter.of(context).push('/settings'),
            ),
            _profileLink(
              Icons.school_outlined,
              l('play'),
              () => GoRouter.of(context).push('/play'),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _profileLink(IconData icon, String title, VoidCallback? onTap) =>
      ListTile(
        leading: Icon(icon, size: 20),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      );

  Future<void> _renameDialog(Session session, L l) async {
    final values = await showLobbyInputs(
      context: context,
      title: l('yourName'),
      confirm: 'OK',
      cancel: l('cancel'),
      fields: [
        LobbyInput(
          label: l('yourName'),
          value: session.user!.name,
          maxLength: 24,
        ),
      ],
    );
    if (values != null && values.first.isNotEmpty && mounted) {
      await _run(() => session.setName(values.first));
    }
  }

  void _sizeDialog(L l) {
    var locked = true;
    var gameType = _filter == 'all' ? 'muushig' : _filter;
    var deckSize = 36;
    var transfer = false;
    var allowDraw = true;
    var size = gameType == 'thousand' ? 3 : 2;
    int maximum() => switch (gameType) {
      'thousand' => 3,
      'durak' => deckSize == 24 ? 4 : 6,
      'mongol13' => 4,
      _ => 5,
    };
    showLobbyDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(l('createRoom')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final entry in {
                      'muushig': 'Muushig',
                      'mongol13': 'Mongol 13',
                      'durak': 'Durak',
                      'thousand': 'Thousand (1000)',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: gameType == entry.key,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: gameType == entry.key
                              ? Theme.of(context).colorScheme.onPrimary
                              : null,
                        ),
                        onSelected: (_) => setDialog(() {
                          gameType = entry.key;
                          size = gameType == 'thousand'
                              ? 3
                              : size.clamp(2, maximum());
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(l('roomVisibility')),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final private in [false, true])
                      ChoiceChip(
                        label: Text(l(private ? 'inviteRoom' : 'publicRoom')),
                        selected: locked == private,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: locked == private
                              ? Theme.of(context).colorScheme.onPrimary
                              : null,
                        ),
                        onSelected: (_) => setDialog(() => locked = private),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l(locked ? 'lockedHint' : 'publicRoomHint'),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                Text(l('players')),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (
                      var n = gameType == 'thousand' ? 3 : 2;
                      n <= maximum();
                      n++
                    )
                      ChoiceChip(
                        key: ValueKey('create-seats-$n'),
                        label: Text('$n'),
                        selected: size == n,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: size == n
                              ? Theme.of(context).colorScheme.onPrimary
                              : null,
                        ),
                        onSelected: (_) => setDialog(() => size = n),
                      ),
                  ],
                ),
                if (gameType == 'durak') ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: deckSize,
                    decoration: InputDecoration(labelText: l('durakDeck')),
                    items: [
                      for (final n in [24, 36, 52])
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: (n) => setDialog(() {
                      deckSize = n ?? 36;
                      size = size.clamp(2, maximum());
                    }),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(l('durakTransferMode')),
                    value: transfer,
                    onChanged: (v) => setDialog(() => transfer = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(l('durakAllowDraw')),
                    value: allowDraw,
                    onChanged: (v) => setDialog(() => allowDraw = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l('cancel')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _createRoom(
                  size,
                  0,
                  locked,
                  gameType,
                  deckSize,
                  transfer,
                  allowDraw,
                );
              },
              child: Text(l('createAndEnter')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _joinDialog(L l) async {
    final values = await showLobbyInputs(
      context: context,
      title: l('roomCode'),
      confirm: l('join'),
      cancel: l('cancel'),
      fields: [
        LobbyInput(
          label: l('roomCode'),
          maxLength: 6,
          keyboard: TextInputType.number,
          validator: (value) => RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')
              ? null
              : l('roomCodeInvalid'),
        ),
      ],
    );
    if (values != null && mounted) _joinRoom(values.first);
  }

  void _inviteDialog(Map<String, dynamic> msg) {
    final l = L(context.read<SettingsController>().lang.value);
    showLobbyDialog<void>(
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
}
