/// Leaderboard: top players by wins, plus the player's own rank.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../net/net_client.dart';
import '../net/session.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';

class RankScreen extends StatefulWidget {
  const RankScreen({super.key});

  @override
  State<RankScreen> createState() => _RankScreenState();
}

class _RankScreenState extends State<RankScreen> {
  List<Map<String, dynamic>>? _top;
  Map<String, dynamic>? _me;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await context.read<Session>().client.call('rank');
      if (!mounted) return;
      setState(() {
        _top = (resp['top'] as List? ?? []).cast<Map<String, dynamic>>();
        _me = resp['me'] as Map<String, dynamic>?;
      });
    } on NetException catch (e) {
      if (mounted) setState(() => _error = e.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();
    final l = L.of(context);
    final uid = context.read<Session>().user?.uid;

    return Scaffold(
      backgroundColor: palette.backgroundMain,
      body: ResponsiveScreen(
        squarishMainArea: Column(
          children: [
            Text(l('leaderboard'),
                style: Theme.of(context).textTheme.headlineMedium),
            if (_me != null)
              Text('${l('rank')}: ${_me!['rank']} · Lv${_me!['level']}'
                  ' · ${l('points')}: ${_me!['rating']}'),
            const SizedBox(height: 8),
            Expanded(
              child: _error != null
                  ? Center(child: Text(l.error(_error!)))
                  : _top == null
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: _top!.length,
                          itemBuilder: (context, i) {
                            final row = _top![i];
                            final mine = row['uid'] == uid;
                            return ListTile(
                              dense: true,
                              leading: Text('${i + 1}'),
                              title: Text(
                                row['name'] as String? ?? '?',
                                style: mine
                                    ? const TextStyle(
                                        fontWeight: FontWeight.bold)
                                    : null,
                              ),
                              trailing: Text(
                                  'Lv${row['level']} · ${row['rating']}'),
                            );
                          },
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
