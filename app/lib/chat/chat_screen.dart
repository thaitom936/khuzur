import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../l10n/strings.dart';
import '../net/net_client.dart';
import '../net/session.dart';
import '../rtc/table_call_controller.dart';
import '../settings/settings.dart';
import '../style/lobby_theme.dart';
import '../style/player_avatar.dart';
import 'chat_audio_waveform.dart';
import 'chat_camera_screen.dart';
import 'chat_composer.dart';
import 'chat_controller.dart';
import 'chat_emoji_picker.dart';
import 'chat_media_preview.dart';
import 'chat_voice_controller.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.channel,
    required this.title,
    this.call,
    this.embedded = false,
    this.active = true,
    this.translucent = false,
  });
  final String channel, title;
  final TableCallController? call;
  final bool embedded, active, translucent;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late ChatController chat;
  late Session chatSession;
  final input = TextEditingController(), scroll = ScrollController();
  final picker = ImagePicker();
  final inputFocus = FocusNode();
  final voice = ChatVoiceController();
  AudioPlayer? voicePreview;
  StreamSubscription<void>? voicePreviewFinished;
  Timer? expiryRefresh;
  bool busy = false, choosingMedia = false, previewingVoice = false;
  double? progress;
  Uint8List? retryBytes;
  String? retryMime;
  bool initialized = false;
  bool restoringScroll = true;
  L get l => L(context.read<SettingsController>().lang.value);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    initialized = true;
    final session = context.read<Session>();
    chatSession = session;
    input.text = session.chatDrafts[widget.channel] ?? '';
    input.addListener(_saveDraft);
    scroll.addListener(_saveScroll);
    final savedOffset = chatSession.chatScrollOffsets[widget.channel] ?? 0;
    WidgetsBinding.instance.addObserver(this);
    voice.addListener(_voiceChanged);
    chat = ChatController(context.read<Session>().client, widget.channel)
      ..addListener(_changed);
    unawaited(
      chat.open().then((_) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (scroll.hasClients) {
            scroll.jumpTo(
              savedOffset.clamp(0, scroll.position.maxScrollExtent),
            );
          }
          restoringScroll = false;
        });
      }),
    );
    expiryRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_recoverPicker());
    }
  }

  void _saveDraft() {
    final drafts = chatSession.chatDrafts;
    if (input.text.isEmpty) {
      drafts.remove(widget.channel);
    } else {
      drafts[widget.channel] = input.text;
    }
  }

  void _saveScroll() {
    if (!restoringScroll && scroll.hasClients) {
      chatSession.chatScrollOffsets[widget.channel] = scroll.offset;
    }
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) {
      inputFocus.unfocus();
      voicePreview?.pause();
      if (voice.active) unawaited(_discardVoice());
    }
  }

  Future<void> _recoverPicker() async {
    try {
      final lost = await picker.retrieveLostData();
      if (mounted && !lost.isEmpty && lost.files?.isNotEmpty == true) {
        // Recovered files use the same explicit preview/send step.
        await _picked(lost.files!.first);
      }
    } catch (_) {
      /* Recovery is optional; normal picking remains available. */
    }
  }

  void _changed() {
    if (!chat.writable && voice.active) unawaited(_discardVoice());
    if (mounted) setState(() {});
  }

  void _voiceChanged() {
    if (mounted) setState(() {});
  }

  void _error(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.error(error is NetException ? error.code : 'generic'),
          ),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      voicePreview?.pause();
      if (previewingVoice && mounted) setState(() => previewingVoice = false);
      final background =
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.detached;
      if (voice.active && (background || voice.stage != VoiceStage.preparing)) {
        unawaited(_discardVoice());
      }
    }
  }

  void _checkLiveCapture() {
    final call = widget.call;
    if (call != null && (call.microphoneOn || call.cameraOn)) {
      throw NetException('chat_capture_busy');
    }
  }

  Future<void> _selectMedia() async {
    if (busy ||
        choosingMedia ||
        voice.active ||
        !chat.writable ||
        !chat.mediaAllowed) {
      return;
    }
    inputFocus.unfocus();
    setState(() => choosingMedia = true);
    try {
      final XFile? file;
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        _checkLiveCapture();
        file = await Navigator.of(context).push<XFile>(
          MaterialPageRoute(builder: (_) => ChatCameraScreen(l: l)),
        );
      } else {
        file = await _pickFromCameraMenu();
      }
      if (file != null && mounted && chat.writable) await _picked(file);
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => choosingMedia = false);
    }
  }

  Future<XFile?> _pickFromCameraMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l('chatPhotosVideos')),
              onTap: () => Navigator.pop(c, 'gallery'),
            ),
            if (picker.supportsImageSource(ImageSource.camera)) ...[
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: Text(l('chatCamera')),
                onTap: () => Navigator.pop(c, 'photo'),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: Text(l('chatRecordVideo')),
                onTap: () => Navigator.pop(c, 'video'),
              ),
            ],
          ],
        ),
      ),
    );
    if (action == null || !mounted || !chat.writable) return null;
    if (action == 'gallery') {
      return picker.pickMedia(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
        requestFullMetadata: false,
      );
    }
    _checkLiveCapture();
    if (action == 'video') {
      return picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 60),
      );
    }
    return picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
  }

  Future<void> _picked(XFile file) async {
    final length = await file.length();
    if (length > 20 * 1024 * 1024) {
      throw NetException('media_too_large');
    }
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();
    final mime = name.endsWith('.mp4')
        ? 'video/mp4'
        : name.endsWith('.mov')
        ? 'video/quicktime'
        : bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216
        ? 'image/jpeg'
        : bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80
        ? 'image/png'
        : bytes.length >= 12 &&
              String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP'
        ? 'image/webp'
        : null;
    if (mime == null) throw NetException('media_bad_file');
    if (mime.startsWith('image/') && length > 5 * 1024 * 1024) {
      throw NetException('media_too_large');
    }
    if (!mounted || !chat.writable || !chat.mediaAllowed) return;
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChatMediaPreview(
          bytes: bytes,
          path: file.path,
          video: mime.startsWith('video/'),
          l: l,
        ),
      ),
    );
    if (confirmed == true && mounted && chat.writable) {
      await _upload(bytes, mime);
    }
  }

  Future<void> _upload(Uint8List bytes, String mime) async {
    if (busy || !chat.writable) return;
    retryBytes = bytes;
    retryMime = mime;
    setState(() {
      busy = true;
      progress = 0;
    });
    final session = context.read<Session>();
    try {
      final grant = await session.client.call('chat_media_prepare', {
        'channel': widget.channel,
        'mime': mime,
        'size': bytes.length,
      });
      if (!mounted) return;
      final request = _UploadRequest(
        Uri.parse(grant['upload_url'] as String),
        bytes,
        (p) {
          if (mounted) setState(() => progress = p);
        },
      )..headers.addAll((grant['headers'] as Map).cast<String, String>());
      final client = http.Client();
      try {
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 120));
        await response.stream.drain<void>();
        if (response.statusCode != 200) {
          throw NetException('media_storage_failed');
        }
      } finally {
        client.close();
      }
      if (!mounted) return;
      setState(() => progress = null);
      await session.client.call('chat_media_complete', {
        'channel': widget.channel,
        'id': grant['id'],
      });
      if (!mounted) return;
      await chat.send(
        '',
        mediaId: grant['id'] as String,
        uid: session.user?.uid,
      );
      retryBytes = null;
      retryMime = null;
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          progress = null;
        });
      }
    }
  }

  Future<void> _startRecording() async {
    if (busy ||
        !widget.active ||
        choosingMedia ||
        !chat.writable ||
        !chat.mediaAllowed ||
        kIsWeb) {
      return;
    }
    try {
      _checkLiveCapture();
      await voice.start();
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _discardVoice() async {
    try {
      final discard = voice.discard();
      await voicePreview?.stop();
      if (mounted) setState(() => previewingVoice = false);
      await discard;
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _pauseVoice() async {
    try {
      await voice.togglePause();
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _sendVoice() async {
    if (busy || voice.working || !chat.writable) return;
    try {
      await voicePreview?.stop();
      if (mounted) setState(() => previewingVoice = false);
      final path = await voice.finish();
      if (path == null || !mounted || !chat.writable) return;
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      await _upload(bytes, 'audio/mp4');
      // Retry bytes remain in memory on upload failure; no recorder/file held.
      await voice.discard();
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _previewVoice() async {
    if (voice.stage != VoiceStage.ready || voice.path == null) return;
    try {
      voicePreview ??= AudioPlayer();
      voicePreviewFinished ??= voicePreview!.onPlayerComplete.listen((_) {
        if (mounted) setState(() => previewingVoice = false);
      });
      if (previewingVoice) {
        await voicePreview!.pause();
      } else {
        await voicePreview!.play(DeviceFileSource(voice.path!));
      }
      if (mounted) setState(() => previewingVoice = !previewingVoice);
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _emoji() async {
    if (!chat.writable || busy || choosingMedia || voice.active) return;
    final selection = input.selection;
    inputFocus.unfocus();
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: chatCream,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ChatEmojiPickerSheet(l: l),
    );
    if (emoji == null || !mounted || !chat.writable) return;
    if (!insertChatEmoji(input, emoji, selection: selection)) {
      _error(NetException('chat_bad_message'));
    }
    inputFocus.requestFocus();
  }

  Future<void> _messageAction(Map<String, dynamic> message) async {
    final own = message['uid'] == context.read<Session>().user?.uid;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (own || chat.moderator)
              ListTile(
                title: Text(l('chatDelete')),
                onTap: () => Navigator.pop(c, 'delete'),
              ),
            if (!own) ...[
              ListTile(
                title: Text(l('chatReport')),
                onTap: () => Navigator.pop(c, 'report'),
              ),
              ListTile(
                title: Text(l('chatBlock')),
                onTap: () => Navigator.pop(c, 'block'),
              ),
              if (chat.moderator)
                ListTile(
                  title: Text(l('chatMute')),
                  onTap: () => Navigator.pop(c, 'mute'),
                ),
            ],
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      await chat.action(
        'chat_$action',
        action == 'block'
            ? {'target': message['uid'], 'on': true}
            : action == 'mute'
            ? {'target': message['uid'], 'seconds': 3600}
            : {'id': message['id'], 'reason': 'User report'},
      );
      if (action == 'block') {
        chat.messages.removeWhere((m) => m['uid'] == message['uid']);
        setState(() {});
      }
    } catch (e) {
      _error(e);
    }
  }

  void _send() {
    final text = input.text.trim();
    if (text.isEmpty || !chat.writable || !widget.active) return;
    input.clear();
    unawaited(chat.send(text, uid: context.read<Session>().user?.uid));
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user;
    final all = [...chat.messages, ...chat.pending.values];
    return LobbyTheme(
      child: Scaffold(
        backgroundColor: widget.translucent ? Colors.transparent : null,
        appBar: widget.embedded ? null : AppBar(title: Text(widget.title)),
        body: Column(
          children: [
            if (chat.error != null)
              MaterialBanner(
                content: Text(l.error(chat.error!)),
                actions: [
                  TextButton(
                    onPressed: () => chat.open(reconnect: true),
                    child: Text(l('retry')),
                  ),
                ],
              ),
            if (chat.closed)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(l('chatClosed')),
              ),
            if (busy)
              Column(
                children: [
                  LinearProgressIndicator(value: progress),
                  Text(l(progress == null ? 'chatVerifying' : 'chatUploading')),
                ],
              ),
            if (retryBytes != null && !busy)
              TextButton(
                onPressed: () => _upload(retryBytes!, retryMime!),
                child: Text(l('chatRetryUpload')),
              ),
            Expanded(
              child: ListView.builder(
                reverse: true,
                controller: scroll,
                padding: const EdgeInsets.all(12),
                itemCount: all.length + 1,
                itemBuilder: (context, index) {
                  if (index == all.length) {
                    return chat.olderAvailable
                        ? TextButton(
                            onPressed: chat.loading ? null : chat.older,
                            child: Text(l('chatOlder')),
                          )
                        : chat.loading
                        ? const Center(child: CircularProgressIndicator())
                        : const SizedBox();
                  }
                  final message = all[all.length - 1 - index];
                  final own = message['uid'] == user?.uid;
                  final deleted = message['deleted'] == true;
                  final sentAt = message['created_at'] is int
                      ? DateTime.fromMillisecondsSinceEpoch(
                          (message['created_at'] as int) * 1000,
                        ).toLocal()
                      : null;
                  final name =
                      message['name'] as String? ??
                      (own ? user?.name : null) ??
                      '?';
                  final body = message['body'] as String? ?? '';
                  final media = !deleted && message['media'] is Map
                      ? Map<String, dynamic>.from(message['media'] as Map)
                      : null;
                  final time = sentAt == null
                      ? null
                      : '${sentAt.hour.toString().padLeft(2, '0')}:${sentAt.minute.toString().padLeft(2, '0')}';
                  final mediaOnly = media != null && body.isEmpty;
                  final mediaAvailable =
                      media != null &&
                      media['expired'] != true &&
                      (media['expires_at'] as int? ?? 0) >
                          DateTime.now().millisecondsSinceEpoch ~/ 1000;
                  final inlineAudioTime =
                      mediaOnly && mediaAvailable && media['kind'] == 'audio';
                  final overlayTime =
                      mediaOnly &&
                      mediaAvailable &&
                      (media['kind'] == 'image' || media['kind'] == 'video');
                  return _MessageRow(
                    own: own,
                    name: name,
                    child: GestureDetector(
                      onLongPress: message['id'] is int
                          ? () => _messageAction(message)
                          : null,
                      child: Card(
                        color: own
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : null,
                        child: Padding(
                          padding: mediaOnly && overlayTime
                              ? const EdgeInsets.all(4)
                              : const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (media != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    children: [
                                      _MediaBubble(
                                        channel: widget.channel,
                                        media: media,
                                        time: inlineAudioTime ? time : null,
                                      ),
                                      if (overlayTime && time != null)
                                        Positioned(
                                          right: 6,
                                          bottom: 6,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 2,
                                                  ),
                                              child: _MessageTime(
                                                time,
                                                onMedia: true,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              if (deleted || body.isNotEmpty)
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: media == null ? 0 : 4,
                                  ),
                                  child: _TimedMessageText(
                                    text: deleted ? l('chatDeleted') : body,
                                    time: time,
                                  ),
                                )
                              else if (!overlayTime &&
                                  !inlineAudioTime &&
                                  time != null)
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: media == null ? 0 : 2,
                                  ),
                                  child: _MessageTime(time),
                                ),
                              if (!deleted &&
                                  message['media_id'] != null &&
                                  message['id'] == null)
                                Text(l('chatAttachment')),
                              if (message['state'] == 'sending')
                                Text(
                                  l('chatSending'),
                                  style: const TextStyle(fontSize: 11),
                                ),
                              if (message['state'] == 'failed')
                                TextButton(
                                  onPressed: () => chat.send(
                                    message['body'] as String,
                                    mediaId: message['media_id'] as String?,
                                    uid: user?.uid,
                                    nonce: message['nonce'] as String,
                                  ),
                                  child: Text(
                                    '${l.error(message['error'] as String? ?? 'generic')} · ${l('retry')}',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            ChatComposer(
              translucent: widget.translucent,
              l: l,
              input: input,
              focus: inputFocus,
              voice: voice,
              writable: chat.writable,
              mediaAllowed: chat.mediaAllowed,
              voiceAllowed: !kIsWeb,
              busy: busy || choosingMedia,
              onSend: _send,
              onCamera: _selectMedia,
              onEmoji: _emoji,
              onRecord: _startRecording,
              onDiscardVoice: _discardVoice,
              onPauseVoice: _pauseVoice,
              onSendVoice: _sendVoice,
              onPreviewVoice: _previewVoice,
              previewingVoice: previewingVoice,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    expiryRefresh?.cancel();
    voice.removeListener(_voiceChanged);
    voice.dispose();
    voicePreviewFinished?.cancel();
    voicePreview?.dispose();
    inputFocus.dispose();
    chat.removeListener(_changed);
    chat.dispose();
    input.removeListener(_saveDraft);
    scroll.removeListener(_saveScroll);
    input.dispose();
    scroll.dispose();
    super.dispose();
  }
}

class _MessageTime extends StatelessWidget {
  const _MessageTime(this.time, {this.onMedia = false});
  final String time;
  final bool onMedia;

  static TextStyle style(BuildContext context, {bool onMedia = false}) =>
      Theme.of(context).textTheme.labelSmall!.copyWith(
        fontSize: 10,
        height: 1.2,
        color: onMedia
            ? Colors.white
            : Theme.of(context).colorScheme.onSurfaceVariant,
      );

  @override
  Widget build(BuildContext context) =>
      Text(time, style: style(context, onMedia: onMedia));
}

/// The trailing placeholder reserves real space for the timestamp, including
/// when it wraps onto another line. Longest-line sizing keeps short bubbles snug.
class _TimedMessageText extends StatelessWidget {
  const _TimedMessageText({required this.text, required this.time});
  final String text;
  final String? time;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final timePainter = TextPainter(
      text: TextSpan(text: time ?? '', style: _MessageTime.style(context)),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: direction,
    )..layout();
    final timeSize = timePainter.size;
    timePainter.dispose();
    return SelectionArea(
      child: Stack(
        children: [
          Text.rich(
            TextSpan(
              text: text,
              children: [
                if (time != null)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.bottom,
                    child: SizedBox(
                      width: timeSize.width + 8,
                      height: timeSize.height,
                    ),
                  ),
              ],
            ),
            style: Theme.of(context).textTheme.bodyMedium,
            textWidthBasis: TextWidthBasis.longestLine,
          ),
          if (time != null)
            Positioned(right: 0, bottom: 0, child: _MessageTime(time!)),
        ],
      ),
    );
  }
}

/// Sender identity sits outside the content bubble for every channel and media type.
class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.name,
    required this.own,
    required this.child,
  });
  final String name;
  final bool own;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final avatar = PlayerAvatar(name: name, size: 32);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: own
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!own) ...[avatar, const SizedBox(width: 8)],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: own
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: name,
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  child,
                ],
              ),
            ),
          ),
          if (own) ...[const SizedBox(width: 8), avatar],
        ],
      ),
    );
  }
}

class _UploadRequest extends http.BaseRequest {
  _UploadRequest(Uri uri, this.bytes, this.progress) : super('PUT', uri);
  final Uint8List bytes;
  final void Function(double) progress;
  @override
  int get contentLength => bytes.length;
  @override
  http.ByteStream finalize() {
    super.finalize();
    Stream<List<int>> chunks() async* {
      for (var i = 0; i < bytes.length; i += 65536) {
        final end = (i + 65536).clamp(0, bytes.length);
        yield bytes.sublist(i, end);
        progress(end / bytes.length);
      }
    }

    return http.ByteStream(chunks());
  }
}

class _MediaBubble extends StatefulWidget {
  const _MediaBubble({required this.channel, required this.media, this.time});
  final String channel;
  final Map<String, dynamic> media;
  final String? time;
  @override
  State<_MediaBubble> createState() => _MediaBubbleState();
}

class _MediaBubbleState extends State<_MediaBubble> {
  Future<String>? thumbnail;
  AudioPlayer? audio;
  bool playing = false;
  bool loadingAudio = false;
  StreamSubscription<PlayerState>? audioStateChanged;
  L get l => L(context.read<SettingsController>().lang.value);
  bool get expired =>
      widget.media['expired'] == true ||
      (widget.media['expires_at'] as int? ?? 0) <=
          DateTime.now().millisecondsSinceEpoch ~/ 1000;
  Future<String> url(bool thumb) async {
    final r = await context.read<Session>().client.call('chat_media_url', {
      'channel': widget.channel,
      'id': widget.media['id'],
      'thumbnail': thumb,
    });
    return r['url'] as String;
  }

  Future<void> open() async {
    if (expired || loadingAudio) return;
    final isAudio = widget.media['kind'] == 'audio';
    if (isAudio) setState(() => loadingAudio = true);
    try {
      if (isAudio && playing) {
        await audio?.stop();
        return;
      }
      final u = await url(false);
      if (!mounted) return;
      if (isAudio) {
        audio ??= AudioPlayer();
        audioStateChanged ??= audio!.onPlayerStateChanged.listen(
          (state) {
            if (mounted) setState(() => playing = state == PlayerState.playing);
          },
          onError: (Object error) {
            if (mounted) setState(() => playing = false);
          },
        );
        await audio!.play(UrlSource(u));
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _MediaViewer(
              url: u,
              video: widget.media['kind'] == 'video',
              title: l(
                widget.media['kind'] == 'video' ? 'chatVideo' : 'chatImage',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (isAudio) setState(() => playing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.error(e is NetException ? e.code : 'generic')),
          ),
        );
      }
    } finally {
      if (isAudio && mounted) setState(() => loadingAudio = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (expired) {
      audio?.stop();
      return Text(l('mediaExpired'));
    }
    final kind = widget.media['kind'];
    if (kind == 'audio') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Tooltip(
              message: l('chatVoice'),
              child: TextButton.icon(
                onPressed: loadingAudio ? null : open,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                  iconSize: 20,
                ),
                icon: Icon(playing ? Icons.stop : Icons.play_arrow),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChatAudioWaveform(playing: playing),
                    const SizedBox(width: 6),
                    Text('${(widget.media['duration'] as num? ?? 0).ceil()}s'),
                  ],
                ),
              ),
            ),
          ),
          if (widget.time != null)
            Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 2),
              child: _MessageTime(widget.time!),
            ),
        ],
      );
    }
    thumbnail ??= url(true);
    return InkWell(
      onTap: open,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 220,
            height: 140,
            child: FutureBuilder<String>(
              future: thumbnail,
              builder: (c, s) => s.hasData
                  ? Image.network(
                      s.data!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, e, st) =>
                          const Icon(Icons.broken_image_outlined),
                    )
                  : const Center(child: Icon(Icons.image_outlined)),
            ),
          ),
          if (kind == 'video')
            const Icon(Icons.play_circle_fill, size: 44, color: Colors.white),
        ],
      ),
    );
  }

  @override
  void dispose() {
    audioStateChanged?.cancel();
    audio?.dispose();
    super.dispose();
  }
}

class _MediaViewer extends StatefulWidget {
  const _MediaViewer({
    required this.url,
    required this.video,
    required this.title,
  });
  final String url, title;
  final bool video;
  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer>
    with WidgetsBindingObserver {
  VideoPlayerController? video;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.video) {
      video = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      video!
          .initialize()
          .then((_) {
            if (mounted) {
              setState(() {});
              video!.play();
            }
          })
          .catchError((Object e) {
            if (mounted) setState(() => error = e.toString());
          });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) video?.pause();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Center(
      child: widget.video
          ? error != null
                ? const Icon(Icons.error_outline)
                : video!.value.isInitialized
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AspectRatio(
                        aspectRatio: video!.value.aspectRatio,
                        child: VideoPlayer(video!),
                      ),
                      VideoProgressIndicator(video!, allowScrubbing: true),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            video!.value.isPlaying
                                ? video!.pause()
                                : video!.play();
                          });
                        },
                        icon: Icon(
                          video!.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                      ),
                    ],
                  )
                : const CircularProgressIndicator()
          : InteractiveViewer(
              child: Image.network(
                widget.url,
                errorBuilder: (_, e, st) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
    ),
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    video?.dispose();
    super.dispose();
  }
}
