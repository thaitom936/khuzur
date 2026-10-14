import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../style/player_avatar.dart';
import 'agora_transport.dart';
import 'table_call_controller.dart';

class TableCallButton extends StatelessWidget {
  const TableCallButton({super.key});

  @override
  Widget build(BuildContext context) {
    final call = context.watch<TableCallController?>();
    if (call == null) return const SizedBox.shrink();
    final l = L.of(context);
    return IconButton(
      tooltip: l('rtcTitle'),
      icon: Icon(
        call.connected ? Icons.headset_mic : Icons.headset_off,
        color: call.connected ? const Color(0xffbaf9df) : null,
      ),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ChangeNotifierProvider.value(
          value: call,
          child: const _CallPanel(),
        ),
      ),
    );
  }
}

class _CallPanel extends StatelessWidget {
  const _CallPanel();

  @override
  Widget build(BuildContext context) {
    final call = context.watch<TableCallController>();
    final l = L.of(context);
    final disabled = call.busy || call.closing;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l('rtcTitle'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                l(
                  !call.supported
                      ? 'rtcAndroidOnly'
                      : call.reconnecting
                      ? 'rtcReconnecting'
                      : call.weakNetwork
                      ? 'rtcWeak'
                      : 'rtcPrivacy',
                ),
                textAlign: TextAlign.center,
              ),
              if (disabled)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                ),
              if (call.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    l.error(call.error!),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(l('rtcRate'), textAlign: TextAlign.center),
              if (call.game.rtcPayer != 0)
                Text(
                  '${l('rtcPayer')}: ${call.game.seats.where((s) => s.rtcUid == call.game.rtcPayer).map((s) => s.name).firstOrNull ?? call.game.rtcPayer}',
                ),
              if (call.game.rtcPayer == call.session.user?.uid)
                Text('${l('rtcBalance')}: ${call.session.user?.coins ?? 0}'),
              if (call.game.rtcEnabled)
                Text(
                  l(
                    call.game.rtc['charging'] == true
                        ? 'rtcCharging'
                        : 'rtcPaused',
                  ),
                ),
              if ((call.game.rtc['blocked'] as String? ?? '').isNotEmpty)
                Text(l.error(call.game.rtc['blocked'] as String)),
              const SizedBox(height: 12),
              ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: disabled || !call.available
                          ? null
                          : () => call.toggleDevice(camera: false),
                      icon: Icon(call.microphoneOn ? Icons.mic : Icons.mic_off),
                      label: Text(
                        l(call.microphoneOn ? 'rtcMicOff' : 'rtcMicOn'),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: disabled || !call.available
                          ? null
                          : () => _toggleCamera(context, call),
                      icon: Icon(
                        call.cameraOn ? Icons.videocam : Icons.videocam_off,
                      ),
                      label: Text(
                        l(call.cameraOn ? 'rtcCameraOff' : 'rtcCameraOn'),
                      ),
                    ),
                    if (call.cameraOn)
                      IconButton(
                        tooltip: l('rtcSwitchCamera'),
                        onPressed: disabled ? null : call.switchCamera,
                        icon: const Icon(Icons.cameraswitch),
                      ),
                  ],
                ),
                for (final seat in call.game.seats)
                  if (!seat.bot &&
                      seat.rtcUid != null &&
                      seat.rtcUid != call.grant?.uid)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CallAvatar(name: seat.name, uid: seat.rtcUid),
                      title: Text(seat.name),
                      trailing: IconButton(
                        tooltip: l(
                          call.muted.contains(seat.rtcUid)
                              ? 'rtcUnmutePeer'
                              : 'rtcMutePeer',
                        ),
                        onPressed: disabled
                            ? null
                            : () => call.toggleMute(seat.rtcUid!),
                        icon: Icon(
                          call.muted.contains(seat.rtcUid)
                              ? Icons.volume_off
                              : Icons.volume_up,
                        ),
                      ),
                    ),
                if (call.connected)
                  TextButton.icon(
                    onPressed: disabled ? null : call.toggleSpeaker,
                    icon: Icon(
                      call.speakerMuted ? Icons.volume_off : Icons.volume_up,
                    ),
                    label: Text(
                      l(call.speakerMuted ? 'rtcSpeakerOn' : 'rtcSpeakerOff'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _toggleCamera(
  BuildContext context,
  TableCallController call,
) async {
  var consent = false;
  if (!call.cameraOn && call.game.rtcPayer == 0) {
    final l = L.of(context);
    consent =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l('rtcPayTitle')),
            content: Text(l('rtcPayBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l('rtcPayConfirm')),
              ),
            ],
          ),
        ) ??
        false;
    if (!consent) return;
  }
  await call.toggleDevice(camera: true, consent: consent);
}

/// Compact in call controls, portrait-shaped at the table. Both use the same
/// video subscription, so changing the layout never changes capture settings.
class CallAvatar extends StatelessWidget {
  final String name;
  final int? uid;
  final Size size;
  final bool portrait;
  const CallAvatar({
    required this.name,
    this.uid,
    this.size = const Size.square(46),
    this.portrait = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final call = context.watch<TableCallController?>();
    final driver = call?.transport;
    final local = uid != null && uid == call?.grant?.uid;
    final showVideo =
        call != null &&
        call.connected &&
        uid != null &&
        (local ? call.cameraOn : call.videos.contains(uid)) &&
        driver is AgoraTransport &&
        driver.engine != null;
    final speaking = uid != null && (call?.speaking(uid!) ?? false);
    final placeholder = portrait
        ? DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xff276f69), const Color(0xff123d3c)],
              ),
            ),
            child: Center(
              child: PlayerAvatar(name: name, size: size.width * .64),
            ),
          )
        : PlayerAvatar(name: name, size: size.width);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(portrait ? 14 : size.width / 2),
            child: SizedBox.expand(
              child: showVideo
                  ? AgoraVideoView(
                      key: ValueKey('rtc-${call.grant!.channel}-$uid'),
                      controller: local
                          ? VideoViewController(
                              rtcEngine: driver.engine!,
                              canvas: const VideoCanvas(uid: 0),
                            )
                          : VideoViewController.remote(
                              rtcEngine: driver.engine!,
                              canvas: VideoCanvas(uid: uid),
                              connection: RtcConnection(
                                channelId: call.grant!.channel,
                              ),
                            ),
                    )
                  : placeholder,
            ),
          ),
          if (speaking ||
              (call?.muted.contains(uid) ?? false) ||
              (portrait &&
                  local &&
                  call?.connected == true &&
                  !call!.microphoneOn))
            Positioned(
              right: portrait ? 6 : 0,
              top: portrait ? 6 : null,
              bottom: portrait ? null : 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Color(0xff164f47),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  speaking
                      ? Icons.graphic_eq
                      : local
                      ? Icons.mic_off
                      : Icons.volume_off,
                  size: portrait ? 16 : 13,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
