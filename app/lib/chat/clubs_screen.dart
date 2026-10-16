import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../net/net_client.dart';
import '../net/session.dart';
import '../settings/settings.dart';
import '../style/lobby_input_dialog.dart';
import '../style/lobby_theme.dart';
import '../style/player_avatar.dart';
import 'chat_screen.dart';

class ClubsScreen extends StatefulWidget {
  const ClubsScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends State<ClubsScreen> {
  List<dynamic> clubs = [];
  Map<String, dynamic>? member;
  bool loading = true, busy = false, wasOnline = false;
  String? error;
  Session? session;
  L get l => L(context.read<SettingsController>().lang.value);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      session = context.read<Session>();
      wasOnline = session!.loggedIn;
      session!.addListener(connectionChanged);
      load();
    });
  }

  void connectionChanged() {
    final online = session!.loggedIn;
    if (online && !wasOnline) load();
    wasOnline = online;
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      final r = await context.read<Session>().client.call('club_list');
      if (!mounted) return;
      setState(() {
        member = r['member'] is Map
            ? Map<String, dynamic>.from(r['member'] as Map)
            : null;
        // The membership is the only club that may be displayed, even with an old server.
        clubs = (r['clubs'] as List? ?? [])
            .where((c) => c['id'] == member?['club_id'])
            .toList();
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = e is NetException ? e.code : 'generic');
      }
    }
    if (mounted) setState(() => loading = false);
  }

  void showError(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.error(e is NetException ? e.code : 'generic')),
        ),
      );
    }
  }

  Future<void> create() async {
    if (busy) return;
    final values = await showLobbyInputs(
      context: context,
      title: l('clubCreate'),
      confirm: l('clubCreate'),
      cancel: l('cancel'),
      fields: [
        LobbyInput(label: l('clubName'), maxLength: 40),
        LobbyInput(label: l('clubDescription'), maxLength: 300, lines: 3),
      ],
    );
    if (values == null || !mounted) return;
    final n = values[0], d = values[1];
    setState(() => busy = true);
    try {
      final r = await context.read<Session>().client.call('club_create', {
        'name': n,
        'description': d,
      });
      if (mounted) await showClub(r['club']['id'] as int);
    } catch (e) {
      showError(e);
    }
    if (mounted) {
      setState(() => busy = false);
      await load();
    }
  }

  Future<void> invitation() async {
    if (busy) return;
    final values = await showLobbyInputs(
      context: context,
      title: l('clubEnterInvite'),
      confirm: l('clubInvitePreview'),
      cancel: l('cancel'),
      fields: [LobbyInput(label: l('clubInviteCode'), maxLength: 32)],
    );
    if (values == null || !mounted) return;
    final entered = values.first.toLowerCase();
    setState(() => busy = true);
    try {
      final client = context.read<Session>().client;
      final preview = await client.call('club_invite_info', {'token': entered});
      if (!mounted) return;
      final club = Map<String, dynamic>.from(preview['club'] as Map);
      final expires = DateTime.fromMillisecondsSinceEpoch(
        (preview['expires_at'] as int) * 1000,
      ).toLocal();
      final confirm = await showLobbyDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(l('clubInvitation')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                club['name'] as String,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Text(l.fmt('clubInviteFrom', preview['inviter'] as String)),
              const SizedBox(height: 8),
              Text(
                l.fmt('clubInviteExpiry', expires.toString().substring(0, 16)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l('clubInviteConfirm')),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) {
        await client.call('club_join', {'token': entered});
        if (mounted) await showClub(club['id'] as int);
      }
    } catch (e) {
      showError(e);
    }
    if (mounted) {
      setState(() => busy = false);
      await load();
    }
  }

  Future<void> showClub(int id) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ClubScreen(id: id)));
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final online = context.watch<Session>().loggedIn;
    return LobbyTheme(
      child: Scaffold(
        appBar: widget.embedded ? null : AppBar(title: Text(l('clubs'))),
        body: RefreshIndicator(
          onRefresh: load,
          child: ListView(
            key: const PageStorageKey('lobby-clubs'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (member == null && !loading) ...[
                FilledButton.icon(
                  onPressed: online && !busy ? create : null,
                  icon: const Icon(Icons.add, size: 20),
                  label: Text(l('clubCreate')),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: online && !busy ? invitation : null,
                  icon: const Icon(Icons.mail_outline, size: 20),
                  label: Text(l('clubEnterInvite')),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                l('clubInviteOnly'),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (loading) const Center(child: CircularProgressIndicator()),
              if (error != null)
                Column(
                  children: [
                    Text(l.error(error!), textAlign: TextAlign.center),
                    TextButton(
                      onPressed: online && !loading ? load : null,
                      child: Text(l('retry')),
                    ),
                  ],
                ),
              for (final c in clubs)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.groups_outlined, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                c['name'] as String,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('${c['members']} ${l('clubMembers')}'),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: online && !busy
                                ? () => showClub(c['id'] as int)
                                : null,
                            child: Text(l('clubMine')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!loading && error == null && member == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      const Icon(Icons.groups_outlined, size: 32),
                      const SizedBox(height: 12),
                      Text(l('clubNoMembership')),
                      const SizedBox(height: 8),
                      Text(l('clubInviteHint'), textAlign: TextAlign.center),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    session?.removeListener(connectionChanged);
    super.dispose();
  }
}

class ClubScreen extends StatefulWidget {
  const ClubScreen({super.key, required this.id});
  final int id;
  @override
  State<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends State<ClubScreen> {
  Map<String, dynamic>? club, member;
  List<dynamic> members = [];
  bool busy = false;
  String? error;
  L get l => L(context.read<SettingsController>().lang.value);
  bool get joined => member?['club_id'] == widget.id;
  bool get owner => joined && member?['role'] == 'owner';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    try {
      final r = await context.read<Session>().client.call('club_info', {
        'id': widget.id,
      });
      if (mounted) {
        setState(() {
          club = Map<String, dynamic>.from(r['club'] as Map);
          members = r['members'] as List? ?? [];
          member = r['member'] is Map
              ? Map<String, dynamic>.from(r['member'] as Map)
              : null;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e is NetException ? e.code : 'generic');
      }
    }
  }

  Future<void> action(String cmd, Map<String, dynamic> args) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await context.read<Session>().client.call(cmd, {
        'id': widget.id,
        ...args,
      });
      if (mounted && cmd == 'club_leave') {
        Navigator.pop(context);
        return;
      }
      if (mounted) await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.error(e is NetException ? e.code : 'generic')),
          ),
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> manage(Map m) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l('clubTransfer')),
              onTap: () => Navigator.pop(c, 'transfer'),
            ),
            ListTile(
              title: Text(l('clubKick')),
              onTap: () => Navigator.pop(c, 'kick'),
            ),
            ListTile(
              title: Text(l('chatMute')),
              onTap: () => Navigator.pop(c, 'mute'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'mute') {
      await action('chat_mute', {
        'channel': 'club:${widget.id}',
        'target': m['uid'],
        'seconds': 3600,
      });
    } else {
      final confirm = await showLobbyDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(l(choice == 'transfer' ? 'clubTransfer' : 'clubKick')),
          content: Text(m['name'] as String),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) {
        await action('club_manage', {'action': choice, 'target': m['uid']});
      }
    }
  }

  Future<void> inviteFriends() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final r = await context.read<Session>().client.call(
        'club_invite_create',
        {'id': widget.id},
      );
      if (!mounted) return;
      final token = r['token'] as String;
      final expires = DateTime.fromMillisecondsSinceEpoch(
        (r['expires_at'] as int) * 1000,
      ).toLocal();
      await showLobbyDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(l('clubInviteCreate')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(token),
              const SizedBox(height: 12),
              Text(
                l.fmt('clubInviteExpiry', expires.toString().substring(0, 16)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(l('cancel')),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: token));
                if (mounted && c.mounted) {
                  Navigator.pop(c);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l('clubInviteCopied'))),
                  );
                }
              },
              icon: const Icon(Icons.copy, size: 18),
              label: Text(l('copy')),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.error(e is NetException ? e.code : 'generic')),
          ),
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> announcement() async {
    final values = await showLobbyInputs(
      context: context,
      title: l('clubDescription'),
      confirm: l('send'),
      cancel: l('cancel'),
      fields: [
        LobbyInput(
          label: l('clubDescription'),
          value: club?['description'] as String? ?? '',
          maxLength: 300,
          lines: 4,
        ),
      ],
    );
    if (values != null && mounted) {
      await action('club_manage', {
        'action': 'description',
        'value': values.first,
      });
    }
  }

  @override
  Widget build(BuildContext context) => LobbyTheme(
    child: Scaffold(
      appBar: AppBar(
        title: Text(club?['name'] as String? ?? l('clubs')),
        actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (error != null) Text(l.error(error!)),
          if (club == null && error == null)
            const Center(child: CircularProgressIndicator()),
          if (club != null) ...[
            Text(club!['description'] as String? ?? ''),
            if (owner)
              TextButton.icon(
                onPressed: announcement,
                icon: const Icon(Icons.edit),
                label: Text(l('clubDescription')),
              ),
            if (owner)
              OutlinedButton.icon(
                onPressed: busy ? null : inviteFriends,
                icon: const Icon(Icons.person_add_alt, size: 20),
                label: Text(l('clubInviteCreate')),
              ),
            if (joined) ...[
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChatScreen(
                      channel: 'club:${widget.id}',
                      title: club!['name'] as String,
                    ),
                  ),
                ),
                icon: const Icon(Icons.chat),
                label: Text(l('clubChat')),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        final ok = await showLobbyDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: Text(l('clubLeave')),
                            content: Text(l('clubLeaveHint')),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: Text(l('cancel')),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && mounted) {
                          await action('club_leave', {});
                        }
                      },
                child: Text(l('clubLeave')),
              ),
            ] else
              Text(l('clubInviteOnly')),
            Text('${members.length} ${l('clubMembers')}'),
            for (final m in members)
              ListTile(
                leading: PlayerAvatar(name: m['name'] as String),
                title: Text(m['name'] as String),
                subtitle: m['role'] == 'owner' ? Text(l('clubOwner')) : null,
                trailing: owner && m['uid'] != context.read<Session>().user?.uid
                    ? IconButton(
                        icon: const Icon(Icons.more_horiz),
                        onPressed: () => manage(m as Map),
                      )
                    : null,
              ),
          ],
        ],
      ),
    ),
  );
}
