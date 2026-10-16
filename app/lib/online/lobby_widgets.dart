import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../style/player_avatar.dart';

const lobbyGreen = Color(0xff183f35);
const lobbyBackground = Color(0xfff5f3ed);
const lobbyMuted = Color(0xff62736b);

enum RoomFilter { all, available, waiting, playing }

/// Room availability is shared by the filter, sorting and action button.
class LobbyRoom {
  final Map<String, dynamic> data;
  const LobbyRoom(this.data);

  String get code => data['code'] as String;
  String get gameType => data['game_type'] as String? ?? 'muushig';
  String get gameName => switch (gameType) {
    'mongol13' => 'Mongol 13',
    'durak' => 'Durak',
    'thousand' => 'Thousand',
    _ => 'Muushig',
  };
  bool get started => data['started'] == true;
  int get size => data['size'] as int? ?? 0;
  int get seated => data['seated'] as int? ?? 0;
  int get bots => data['bots'] as int? ?? 0;
  int get humans => (seated - bots).clamp(0, size);
  int get stake => data['stake'] as int? ?? 0;
  // One game is one sitting: no joining once play has started.
  bool get canSit => !started && seated < size;
  bool get practice => data['mode'] == 'bot';
  bool matches(RoomFilter filter) => switch (filter) {
    RoomFilter.all => true,
    RoomFilter.available => canSit,
    RoomFilter.waiting => !started,
    RoomFilter.playing => started,
  };
}

/// Each room is represented by its players, with one spectator-first entry.
class LobbyRoomCard extends StatelessWidget {
  final LobbyRoom room;
  final L l;
  final bool enabled;
  final VoidCallback onJoin;

  const LobbyRoomCard({
    super.key,
    required this.room,
    required this.l,
    required this.enabled,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final names = (room.data['names'] as List? ?? []).cast<String>();
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${room.gameName} · ${l('join')} ${room.code}',
      child: Material(
        key: ValueKey('room-${room.code}'),
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onJoin : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.gameName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < room.size; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (i < names.length)
                                PlayerAvatar(name: names[i], size: 36)
                              else
                                const CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Color(0xffedf2ed),
                                  child: Icon(
                                    Icons.person_add_alt,
                                    size: 20,
                                    color: lobbyMuted,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Tooltip(
                                message: i < names.length
                                    ? names[i]
                                    : l('openSeat'),
                                child: Text(
                                  i < names.length ? names[i] : l('openSeat'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LobbyNotice extends StatelessWidget {
  final String message;
  final String? action;
  final VoidCallback? onAction;
  const LobbyNotice({
    super.key,
    required this.message,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(
          Icons.info_outline,
          size: 20,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}
