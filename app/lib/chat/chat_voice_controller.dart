import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../net/net_client.dart';
import 'chat_controller.dart';

enum VoiceStage { idle, preparing, recording, paused, ready }

abstract interface class VoiceCapture {
  Future<bool> hasPermission();
  Future<void> start(String path);
  Future<void> pause();
  Future<void> resume();
  Future<String?> stop();
  Future<void> cancel();
  Future<void> dispose();
  Stream<double> get amplitude;
}

class NativeVoiceCapture implements VoiceCapture {
  AudioRecorder? _recorder;
  AudioRecorder get recorder => _recorder ??= AudioRecorder();
  @override
  Future<bool> hasPermission() => recorder.hasPermission();
  @override
  Future<void> start(String path) => recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 64000,
      sampleRate: 24000,
      numChannels: 1,
    ),
    path: path,
  );
  @override
  Future<void> pause() => recorder.pause();
  @override
  Future<void> resume() => recorder.resume();
  @override
  Future<String?> stop() => recorder.stop();
  @override
  Future<void> cancel() async => _recorder?.cancel();
  @override
  Future<void> dispose() async => _recorder?.dispose();
  @override
  Stream<double> get amplitude => recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((value) => value.current);
}

/// Owns the unsent recording. Pausing and the 60-second limit never send it.
/// Native operations are serialized so closing during permission/start cannot
/// leave a microphone running after the screen has gone away.
class ChatVoiceController extends ChangeNotifier {
  ChatVoiceController({
    VoiceCapture? capture,
    Future<String> Function()? createPath,
    DateTime Function()? now,
  }) : _capture = capture ?? NativeVoiceCapture(),
       _createPath = createPath ?? _temporaryPath,
       _now = now ?? DateTime.now;

  final VoiceCapture _capture;
  final Future<String> Function() _createPath;
  final DateTime Function() _now;
  VoiceStage stage = VoiceStage.idle;
  final List<double> samples = [];
  String? path;
  Duration _elapsed = Duration.zero;
  DateTime? _segment;
  Timer? _ticker, _limit;
  StreamSubscription<double>? _levels;
  Future<void> _tail = Future.value();
  bool _disposed = false, working = false;
  int _generation = 0;
  static const maxDuration = Duration(seconds: 60);
  bool get active => stage != VoiceStage.idle;
  bool get capturing => stage == VoiceStage.recording;
  Duration get duration {
    final segment = _segment;
    final value =
        _elapsed +
        (segment == null ? Duration.zero : _now().difference(segment));
    return value < maxDuration ? value : maxDuration;
  }

  static Future<String> _temporaryPath() async =>
      '${(await getTemporaryDirectory()).path}/khuzur-${chatNonce()}.m4a';

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (_disposed || active) return;
    final generation = ++_generation;
    stage = VoiceStage.preparing;
    samples.clear();
    _notify();
    try {
      await _serial(() async {
        final allowed = await _capture.hasPermission();
        if (_disposed || generation != _generation) return;
        if (!allowed) throw NetException('chat_mic_denied');
        path = await _createPath();
        if (_disposed || generation != _generation) return;
        await _capture.start(path!);
        if (_disposed || generation != _generation) {
          await _capture.cancel();
          return;
        }
        _elapsed = Duration.zero;
        _segment = _now();
        stage = VoiceStage.recording;
        _levels = _capture.amplitude.listen((db) {
          if (!capturing || _disposed) return;
          samples.add(db.isFinite ? ((db + 60) / 60).clamp(0.04, 1) : 0.04);
          if (samples.length > 100) samples.removeAt(0);
          _notify();
        }, onError: (Object _) {});
        _ticker = Timer.periodic(
          const Duration(milliseconds: 100),
          (_) => _notify(),
        );
        _armLimit();
        _notify();
      });
    } catch (_) {
      if (generation == _generation && !_disposed) {
        await discard();
        rethrow;
      }
    }
  }

  void _armLimit() {
    _limit?.cancel();
    _limit = Timer(
      maxDuration - duration,
      () => unawaited(finish().catchError((Object _) => null)),
    );
  }

  Future<void> togglePause() async {
    if (_disposed ||
        working ||
        (stage != VoiceStage.recording && stage != VoiceStage.paused)) {
      return;
    }
    working = true;
    final generation = _generation;
    _notify();
    try {
      await _serial(() async {
        if (generation != _generation || _disposed) return;
        if (capturing) {
          await _capture.pause();
          if (generation != _generation || _disposed) return;
          _elapsed = duration;
          _segment = null;
          _limit?.cancel();
          stage = VoiceStage.paused;
        } else {
          await _capture.resume();
          if (generation != _generation || _disposed) return;
          _segment = _now();
          stage = VoiceStage.recording;
          _armLimit();
        }
      });
    } finally {
      working = false;
      _notify();
    }
  }

  Future<String?> finish() async {
    if (_disposed ||
        stage == VoiceStage.idle ||
        stage == VoiceStage.preparing) {
      return null;
    }
    if (stage == VoiceStage.ready) return path;
    working = true;
    final generation = _generation;
    _notify();
    try {
      return await _serial(() async {
        if (generation != _generation || _disposed) return null;
        if (stage == VoiceStage.ready) return path;
        _elapsed = duration;
        _segment = null;
        _limit?.cancel();
        _ticker?.cancel();
        await _levels?.cancel();
        _levels = null;
        final result = await _capture.stop();
        if (generation != _generation || _disposed) return null;
        path = result ?? path;
        stage = VoiceStage.ready;
        return path;
      });
    } finally {
      working = false;
      _notify();
    }
  }

  Future<void> discard() async {
    ++_generation;
    _limit?.cancel();
    _ticker?.cancel();
    await _levels?.cancel();
    _levels = null;
    stage = VoiceStage.idle;
    _segment = null;
    _elapsed = Duration.zero;
    samples.clear();
    _notify();
    await _serial(() async {
      try {
        await _capture.cancel();
      } finally {
        final saved = path;
        path = null;
        if (saved != null) {
          final file = File(saved);
          if (await file.exists()) await file.delete();
        }
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(
      discard().whenComplete(_capture.dispose).catchError((Object _) {}),
    );
    super.dispose();
  }
}
