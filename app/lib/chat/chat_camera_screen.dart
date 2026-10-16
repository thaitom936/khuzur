import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/strings.dart';

/// Camera resources belong to this route and are released before preview/send.
class ChatCameraScreen extends StatefulWidget {
  const ChatCameraScreen({super.key, required this.l});
  final L l;
  @override
  State<ChatCameraScreen> createState() => _ChatCameraScreenState();
}

class _ChatCameraScreenState extends State<ChatCameraScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> cameras = [];
  CameraController? camera;
  bool videoMode = false, busy = true, recording = false, foreground = true;
  FlashMode flash = FlashMode.off;
  double zoom = 1, maxZoom = 1, minZoom = 1;
  int selected = 0, generation = 0, seconds = 0;
  String? error;
  Timer? ticker, limit;
  Future<void> released = Future.value();
  L get l => widget.l;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _release() async {
    ++generation;
    ticker?.cancel();
    limit?.cancel();
    final old = camera;
    camera = null;
    recording = false;
    final pending = released.then((_) async {
      if (old == null) return;
      try {
        if (old.value.isRecordingVideo) {
          final abandoned = await old.stopVideoRecording();
          final file = File(abandoned.path);
          if (await file.exists()) await file.delete();
        }
      } catch (_) {
        // Disposing still releases capture after an interrupted recording.
      } finally {
        await old.dispose();
      }
    });
    released = pending.catchError((Object _) {});
    await released;
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        busy = true;
        error = null;
      });
    }
    await _release();
    final current = generation;
    CameraController? next;
    try {
      if (cameras.isEmpty) cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('CameraNotFound', '');
      if (!mounted || !foreground || current != generation) return;
      next = CameraController(
        cameras[selected % cameras.length],
        ResolutionPreset.high,
        enableAudio: videoMode,
      );
      camera = next;
      await next.initialize();
      if (!mounted || !foreground || current != generation) return;
      minZoom = await next.getMinZoomLevel();
      maxZoom = await next.getMaxZoomLevel();
      zoom = minZoom.clamp(1, maxZoom);
      await next.setZoomLevel(zoom);
      // Some front cameras do not provide flash. Keep capture available.
      try {
        await next.setFlashMode(flash);
      } catch (_) {
        flash = FlashMode.off;
      }
    } on CameraException catch (e) {
      if (mounted && current == generation) {
        error = l(
          e.code.startsWith('AudioAccess')
              ? 'error_chat_mic_denied'
              : 'chatCameraUnavailable',
        );
      }
    } catch (_) {
      if (mounted && current == generation) error = l('chatCameraUnavailable');
    } finally {
      if (mounted && current == generation) setState(() => busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      foreground = false;
      unawaited(_release());
      if (mounted) setState(() => busy = true);
    } else if (state == AppLifecycleState.inactive &&
        camera?.value.isInitialized == true) {
      foreground = false;
      unawaited(_release());
      if (mounted) setState(() => busy = true);
    } else if (state == AppLifecycleState.resumed) {
      final resume = !foreground;
      foreground = true;
      if (resume) unawaited(_initialize());
    }
  }

  Future<void> _capture() async {
    final capture = camera;
    if (busy || capture == null || !capture.value.isInitialized) return;
    setState(() => busy = true);
    try {
      if (!videoMode) {
        final file = await capture.takePicture();
        if (!mounted || camera != capture || !foreground) return;
        await _return(file);
      } else if (recording) {
        ticker?.cancel();
        limit?.cancel();
        final file = await capture.stopVideoRecording();
        recording = false;
        if (!mounted || camera != capture || !foreground) {
          final abandoned = File(file.path);
          if (await abandoned.exists()) await abandoned.delete();
          return;
        }
        await _return(file);
      } else {
        await capture.startVideoRecording();
        if (!mounted || camera != capture || !foreground) return;
        seconds = 0;
        recording = true;
        ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => seconds++);
        });
        // Stop below the server's 60-second ceiling to allow encoder overhead.
        limit = Timer(const Duration(seconds: 59), () => unawaited(_capture()));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l('chatCameraUnavailable'))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _return(XFile file) async {
    await _release();
    if (mounted) Navigator.pop(context, file);
  }

  Future<void> _gallery() async {
    if (busy || recording) return;
    setState(() => busy = true);
    await _release();
    try {
      final picker = ImagePicker();
      final file = videoMode
          ? await picker.pickVideo(
              source: ImageSource.gallery,
              maxDuration: const Duration(seconds: 60),
            )
          : await picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 1600,
              maxHeight: 1600,
              imageQuality: 80,
            );
      if (!mounted) return;
      if (file != null) {
        await _return(file);
        return;
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l('chatCameraUnavailable'))));
      }
    }
    if (mounted && foreground) await _initialize();
  }

  Future<void> _toggleFlash() async {
    final capture = camera;
    if (capture == null || busy || recording) return;
    final next = flash == FlashMode.off
        ? FlashMode.auto
        : flash == FlashMode.auto
        ? FlashMode.always
        : FlashMode.off;
    try {
      await capture.setFlashMode(next);
      if (mounted) setState(() => flash = next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l('chatFlashUnavailable'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final capture = camera;
    return PopScope(
      canPop: !recording,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && recording) {
          unawaited(
            _release().then((_) {
              if (context.mounted) Navigator.pop(context);
            }),
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (capture != null && capture.value.isInitialized)
                      ClipRect(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: capture.value.previewSize!.height,
                            height: capture.value.previewSize!.width,
                            child: CameraPreview(capture),
                          ),
                        ),
                      )
                    else if (error != null)
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.no_photography_outlined,
                              color: Colors.white70,
                              size: 42,
                            ),
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            TextButton(
                              onPressed: _initialize,
                              child: Text(l('retry')),
                            ),
                          ],
                        ),
                      )
                    else
                      const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _cameraButton(Icons.close, l('cancel'), () async {
                        await _release();
                        if (context.mounted) Navigator.pop(context);
                      }),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _cameraButton(
                        flash == FlashMode.off
                            ? Icons.flash_off
                            : flash == FlashMode.auto
                            ? Icons.flash_auto
                            : Icons.flash_on,
                        l('chatFlash'),
                        busy || recording ? null : _toggleFlash,
                      ),
                    ),
                    if (recording)
                      Positioned(
                        top: 20,
                        left: 90,
                        right: 90,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade700,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '0:${seconds.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 20,
                      left: 22,
                      right: 22,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _cameraButton(
                            Icons.photo_library_outlined,
                            l('chatPhotosVideos'),
                            busy || recording ? null : _gallery,
                          ),
                          Semantics(
                            label: l(
                              recording
                                  ? 'chatStopRecording'
                                  : videoMode
                                  ? 'chatRecordVideo'
                                  : 'chatCamera',
                            ),
                            button: true,
                            child: GestureDetector(
                              onTap: busy ? null : _capture,
                              child: Container(
                                width: 82,
                                height: 82,
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 4,
                                  ),
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  margin: EdgeInsets.all(recording ? 17 : 0),
                                  decoration: BoxDecoration(
                                    color: videoMode
                                        ? Colors.red
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(
                                      recording ? 7 : 50,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _cameraButton(
                            Icons.flip_camera_ios_outlined,
                            l('chatFlipCamera'),
                            busy || recording || cameras.length < 2
                                ? null
                                : () {
                                    selected = (selected + 1) % cameras.length;
                                    unawaited(_initialize());
                                  },
                          ),
                        ],
                      ),
                    ),
                    if (maxZoom > minZoom &&
                        !recording &&
                        !busy &&
                        error == null)
                      Positioned(
                        bottom: 120,
                        left: 100,
                        right: 100,
                        child: Row(
                          children: [
                            Text(
                              '${zoom.toStringAsFixed(1)}×',
                              style: const TextStyle(color: Colors.white),
                            ),
                            Expanded(
                              child: Slider(
                                value: zoom,
                                min: minZoom,
                                max: maxZoom.clamp(minZoom, 4),
                                activeColor: Colors.white,
                                onChanged: (value) {
                                  setState(() => zoom = value);
                                  unawaited(
                                    capture!
                                        .setZoomLevel(value)
                                        .catchError((Object _) {}),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [false, true]
                      .map(
                        (video) => TextButton(
                          onPressed: busy || recording || videoMode == video
                              ? null
                              : () {
                                  videoMode = video;
                                  unawaited(_initialize());
                                },
                          style: TextButton.styleFrom(
                            foregroundColor: videoMode == video
                                ? Colors.amber
                                : Colors.white70,
                            disabledForegroundColor: videoMode == video
                                ? Colors.amber
                                : Colors.white38,
                          ),
                          child: Text(
                            l(video ? 'chatVideo' : 'chatPhoto'),
                            style: const TextStyle(fontSize: 17),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cameraButton(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed,
  ) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: const Color(0x66202020),
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white38,
      minimumSize: const Size(48, 48),
    ),
    icon: Icon(icon, size: 27),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_release());
    super.dispose();
  }
}
