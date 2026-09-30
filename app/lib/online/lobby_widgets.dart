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
      label: '${l('join')} ${room.code}',
      child: Material(
        key: ValueKey('room-${room.code}'),
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xffe0e5df)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onJoin : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final name in names)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PlayerAvatar(name: name, size: 36),
                          const SizedBox(height: 8),
                          Tooltip(
                            message: name,
                            child: Text(
                              name,
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
      color: const Color(0xfffff2da),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, size: 20, color: Color(0xff79551d)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Color(0xff79551d)),
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}
