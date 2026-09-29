import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../game/remote_game.dart';
import '../l10n/strings.dart';
import '../net/net_client.dart';
import '../net/session.dart';

/// Watching never occupies a seat. Joining is an explicit, separate action.
class SpectatorControls extends StatefulWidget {
  final RemoteGameController game;
  const SpectatorControls({super.key, required this.game});

  @override
  State<SpectatorControls> createState() => _SpectatorControlsState();
}

class _SpectatorControlsState extends State<SpectatorControls> {
  bool _joining = false;
  String? _error;

  Future<void> _sit() async {
    if (_joining) return;
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      await widget.game.takeSeat();
      if (mounted && !widget.game.started) GoRouter.of(context).go('/online');
    } on NetException catch (e) {
      if (mounted) setState(() => _error = e.code);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final connected = context.watch<Session>().loggedIn;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l.error(_error!),
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l(widget.game.gameOver ? 'gameOver' : 'spectating'),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FilledButton.icon(
                  onPressed: connected && widget.game.canTakeSeat && !_joining
                      ? _sit
                      : null,
                  icon: _joining
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.event_seat_outlined, size: 18),
                  label: Text(
                    l(widget.game.canTakeSeat ? 'sit' : 'noSeatAvailable'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
