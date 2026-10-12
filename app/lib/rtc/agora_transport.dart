import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';

class CallGrant {
  final String appId, channel, token;
  final int uid, renewAfter;

  CallGrant.fromJson(Map<String, dynamic> json)
    : appId = json['app_id'] as String,
      channel = json['channel'] as String,
      token = json['token'] as String,
      uid = json['uid'] as int,
      renewAfter = json['renew_after'] as int;
}

/// Small boundary for lifecycle/permission tests without native devices.
abstract class CallTransport {
  void Function(int uid, bool enabled)? onVideo;
  void Function(Map<int, int> levels)? onLevels;
  void Function(bool reconnecting)? onConnection;
  void Function(bool weak)? onQuality;
  void Function()? onRenew;
  void Function()? onFailure;

  Future<void> connect(CallGrant grant);
  Future<bool> permission({required bool camera});
  Future<void> microphone(bool enabled);
  Future<void> camera(bool enabled);
  Future<void> mutePeer(int uid, bool muted);
  Future<void> switchCamera();
  Future<void> renew(String token);
  Future<void> close();
}

class AgoraTransport extends CallTransport {
  RtcEngine? engine;
  RtcEngineEventHandler? _handler;
  bool _microphone = false, _camera = false;
  Future<void>? _closing;

  @override
  Future<void> connect(CallGrant grant) async {
    final rtc = engine = createAgoraRtcEngine();
    final joined = Completer<void>();
    var joinFailed = false;
    await rtc.initialize(
      RtcEngineContext(
        appId: grant.appId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ),
    );
    _handler = RtcEngineEventHandler(
      onJoinChannelSuccess: (_, _) {
        if (!joined.isCompleted) joined.complete();
      },
      onError: (_, _) {
        if (!joined.isCompleted) {
          joinFailed = true;
          joined.complete();
        } else {
          onFailure?.call();
        }
      },
      onConnectionStateChanged: (_, state, _) {
        onConnection?.call(
          state == ConnectionStateType.connectionStateReconnecting,
        );
        if (state == ConnectionStateType.connectionStateFailed) {
          onFailure?.call();
        }
      },
      onUserOffline: (_, uid, _) => onVideo?.call(uid, false),
      onRemoteVideoStateChanged: (_, uid, state, _, _) => onVideo?.call(
        uid,
        state == RemoteVideoState.remoteVideoStateDecoding,
      ),
      onAudioVolumeIndication: (_, speakers, _, _) => onLevels?.call({
        for (final speaker in speakers)
          (speaker.uid == 0 ? grant.uid : speaker.uid ?? 0):
              speaker.volume ?? 0,
      }),
      onNetworkQuality: (_, uid, tx, rx) {
        if (uid == 0) {
          onQuality?.call(
            tx == QualityType.qualityBad ||
                tx == QualityType.qualityVbad ||
                tx == QualityType.qualityDown ||
                rx == QualityType.qualityBad ||
                rx == QualityType.qualityVbad ||
                rx == QualityType.qualityDown,
          );
        }
      },
      onTokenPrivilegeWillExpire: (_, _) => onRenew?.call(),
      onRequestToken: (_) => onRenew?.call(),
    );
    rtc.registerEventHandler(_handler!);
    // No preview and no device permission requests on entry. Disable capture
    // before enabling receive-side video and before joining as an audience.
    await rtc.enableLocalAudio(false);
    await rtc.enableLocalVideo(false);
    await rtc.enableVideo();
    await rtc.enableLocalVideo(false);
    await rtc.setVideoEncoderConfiguration(
      const VideoEncoderConfiguration(
        dimensions: VideoDimensions(width: 320, height: 240),
        frameRate: 15,
        bitrate: 200,
      ),
    );
    await rtc.setDualStreamMode(
      mode: SimulcastStreamMode.enableSimulcastStream,
    );
    await rtc.setRemoteDefaultVideoStreamType(VideoStreamType.videoStreamLow);
    await rtc.setRemoteSubscribeFallbackOption(
      StreamFallbackOptions.streamFallbackOptionAudioOnly,
    );
    await rtc.enableAudioVolumeIndication(
      interval: 300,
      smooth: 3,
      reportVad: true,
    );
    await rtc.joinChannel(
      token: grant.token,
      channelId: grant.channel,
      uid: grant.uid,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleAudience,
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
        publishMicrophoneTrack: false,
        publishCameraTrack: false,
        enableAudioRecordingOrPlayout: true,
      ),
    );
    await joined.future.timeout(const Duration(seconds: 15));
    if (joinFailed) throw StateError('rtc_failed');
  }

  Future<void> _publish() => engine!.updateChannelMediaOptions(
    ChannelMediaOptions(
      clientRoleType: _microphone || _camera
          ? ClientRoleType.clientRoleBroadcaster
          : ClientRoleType.clientRoleAudience,
      publishMicrophoneTrack: _microphone,
      publishCameraTrack: _camera,
    ),
  );

  @override
  Future<bool> permission({required bool camera}) async =>
      (await (camera ? Permission.camera : Permission.microphone).request())
          .isGranted;

  @override
  Future<void> microphone(bool enabled) async {
    await engine!.enableLocalAudio(enabled);
    _microphone = enabled;
    await _publish();
  }

  @override
  Future<void> camera(bool enabled) async {
    await engine!.enableLocalVideo(enabled);
    _camera = enabled;
    await _publish();
  }

  @override
  Future<void> mutePeer(int uid, bool muted) =>
      engine!.muteRemoteAudioStream(uid: uid, mute: muted);
  @override
  Future<void> switchCamera() => engine!.switchCamera();
  @override
  Future<void> renew(String token) => engine!.renewToken(token);

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    final rtc = engine;
    engine = null;
    if (rtc == null) return;
    if (_handler != null) rtc.unregisterEventHandler(_handler!);
    try {
      await rtc.leaveChannel();
    } finally {
      await rtc.release();
    }
  }
}
