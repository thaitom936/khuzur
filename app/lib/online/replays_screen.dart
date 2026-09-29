/// Recent games of this player; tapping one opens the replay viewer.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../net/net_client.dart';
import '../net/session.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';

class ReplaysScreen extends StatefulWidget {
  const ReplaysScreen({super.key});

  @override
  State<ReplaysScreen> createState() => _ReplaysScreenState();
}

class _ReplaysScreenState extends State<ReplaysScreen> {
  List<Map<String, dynamic>>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await context.read<Session>().client.call('replays');
      if (!mounted) return;
      setState(() =>
          _list = (resp['list'] as List? ?? []).cast<Map<String, dynamic>>());
    } on NetException catch (e) {
      if (mounted) setState(() => _error = e.code);
    }
  }

  Future<void> _open(int id) async {
    try {
      final resp =
          await context.read<Session>().client.call('replay', {'id': id});
      if (!mounted) return;
      final record =
          jsonDecode(resp['replay'] as String) as Map<String, dynamic>;
      GoRouter.of(context).push('/online/replay', extra: record);
    } on NetException catch (e) {
      if (mounted) setState(() => _error = e.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();
    final l = L.of(context);

    return Scaffold(
      backgroundColor: palette.backgroundMain,
      body: ResponsiveScreen(
        squarishMainArea: Column(
          children: [
            Text(l('replays'),
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Expanded(
              child: _error != null
                  ? Center(child: Text(l.error(_error!)))
                  : _list == null
                      ? const Center(child: CircularProgressIndicator())
                      : _list!.isEmpty
                          ? Center(child: Text(l('noReplays')))
                          : ListView(
                              children: [
                                for (final r in _list!)
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.movie),
                                    title: Text((r['names'] as List? ?? [])
                                        .join(' · ')),
                                    subtitle: Text(DateTime
                                            .fromMillisecondsSinceEpoch(
                                                (r['ts'] as int) * 1000)
                                        .toString()
                                        .substring(0, 16)),
                                    onTap: () => _open(r['id'] as int),
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
