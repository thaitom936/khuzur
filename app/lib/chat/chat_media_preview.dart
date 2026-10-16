import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../l10n/strings.dart';
import 'chat_composer.dart';

class ChatMediaPreview extends StatefulWidget {
  const ChatMediaPreview({
    super.key,
    required this.bytes,
    required this.path,
    required this.video,
    required this.l,
  });
  final Uint8List bytes;
  final String path;
  final bool video;
  final L l;
  @override
  State<ChatMediaPreview> createState() => _ChatMediaPreviewState();
}

class _ChatMediaPreviewState extends State<ChatMediaPreview>
    with WidgetsBindingObserver {
  VideoPlayerController? video;
  String? error;
  bool get ready =>
      error == null && (!widget.video || video?.value.isInitialized == true);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.video) {
      video = kIsWeb
          ? VideoPlayerController.networkUrl(Uri.parse(widget.path))
          : VideoPlayerController.file(File(widget.path));
      video!
          .initialize()
          .then((_) {
            if (!mounted) return;
            setState(() {
              if (video!.value.duration >
                  const Duration(seconds: 60, milliseconds: 100)) {
                error = widget.l('error_media_bad_duration');
              }
            });
          })
          .catchError((Object _) {
            if (mounted) {
              setState(() => error = widget.l('error_media_bad_file'));
            }
          });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) video?.pause();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff101a16),
    appBar: AppBar(
      backgroundColor: const Color(0xff101a16),
      foregroundColor: Colors.white,
      leading: IconButton(
        key: const Key('chat-preview-cancel'),
        tooltip: widget.l('cancel'),
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context, false),
      ),
      title: Text(widget.l('chatPreview')),
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : widget.video
                  ? ready
                        ? Stack(
                            alignment: Alignment.center,
                            children: [
                              AspectRatio(
                                aspectRatio: video!.value.aspectRatio,
                                child: VideoPlayer(video!),
                              ),
                              IconButton.filled(
                                tooltip: widget.l(
                                  video!.value.isPlaying
                                      ? 'chatPausePreview'
                                      : 'chatPlayVideo',
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black45,
                                  foregroundColor: Colors.white,
                                ),
                                iconSize: 45,
                                icon: Icon(
                                  video!.value.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                                onPressed: () {
                                  setState(() {
                                    video!.value.isPlaying
                                        ? video!.pause()
                                        : video!.play();
                                  });
                                },
                              ),
                            ],
                          )
                        : const CircularProgressIndicator(color: Colors.white)
                  : InteractiveViewer(
                      child: Image.memory(
                        widget.bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) {
                          if (error == null) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(
                                  () =>
                                      error = widget.l('error_media_bad_file'),
                                );
                              }
                            });
                          }
                          return const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white70,
                            size: 50,
                          );
                        },
                      ),
                    ),
            ),
          ),
          if (widget.video && ready)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: VideoProgressIndicator(
                video!,
                allowScrubbing: true,
                colors: const VideoProgressColors(playedColor: chatGreen),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.l('chatPreviewHint'),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  key: const Key('chat-preview-send'),
                  tooltip: widget.l('send'),
                  style: IconButton.styleFrom(
                    backgroundColor: chatGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(54, 54),
                  ),
                  onPressed: ready
                      ? () {
                          video?.pause();
                          Navigator.pop(context, true);
                        }
                      : null,
                  icon: const Icon(Icons.send_rounded, size: 27),
                ),
              ],
            ),
          ),
        ],
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
