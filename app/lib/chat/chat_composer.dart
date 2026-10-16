import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'chat_voice_controller.dart';

const chatCream = Color(0xfff3f0e8);
const chatGreen = Color(0xff00a86b);

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.l,
    required this.input,
    required this.focus,
    required this.voice,
    required this.writable,
    required this.mediaAllowed,
    required this.voiceAllowed,
    required this.busy,
    required this.onSend,
    required this.onCamera,
    required this.onEmoji,
    required this.onRecord,
    required this.onDiscardVoice,
    required this.onPauseVoice,
    required this.onSendVoice,
    required this.onPreviewVoice,
    this.previewingVoice = false,
    this.translucent = false,
  });
  final L l;
  final TextEditingController input;
  final FocusNode focus;
  final ChatVoiceController voice;
  final bool writable, mediaAllowed, voiceAllowed, busy, previewingVoice;
  final bool translucent;
  final VoidCallback onSend,
      onCamera,
      onEmoji,
      onRecord,
      onDiscardVoice,
      onPauseVoice,
      onSendVoice,
      onPreviewVoice;

  @override
  Widget build(BuildContext context) => Material(
    color: translucent
        ? Colors.transparent
        : Theme.of(context).scaffoldBackgroundColor,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
        child: ListenableBuilder(
          listenable: Listenable.merge([input, voice]),
          builder: (context, _) {
            if (voice.active) return _voiceBar(context);
            final hasText = input.text.trim().isNotEmpty;
            final enabled = writable && !busy;
            final showMic = mediaAllowed && voiceAllowed && !hasText;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('chat-input'),
                            controller: input,
                            focusNode: focus,
                            maxLength: 500,
                            minLines: 1,
                            maxLines: 4,
                            enabled: enabled,
                            textCapitalization: TextCapitalization.sentences,
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: l(
                                writable ? 'chatPlaceholder' : 'chatReadOnly',
                              ),
                              hintStyle: const TextStyle(
                                fontSize: 14,
                                color: Color(0xff838a85),
                              ),
                              counterText: '',
                              isDense: true,
                              contentPadding: const EdgeInsets.fromLTRB(
                                14,
                                13,
                                0,
                                13,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const Key('chat-emoji'),
                          tooltip: l('chatEmoji'),
                          onPressed: enabled ? onEmoji : null,
                          icon: const Icon(
                            Icons.emoji_emotions_outlined,
                            size: 23,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (mediaAllowed && !hasText)
                  IconButton(
                    key: const Key('chat-camera'),
                    tooltip: l('chatCamera'),
                    onPressed: enabled ? onCamera : null,
                    icon: const Icon(Icons.camera_alt_outlined),
                  )
                else
                  const SizedBox(width: 6),
                _RoundAction(
                  key: Key(showMic ? 'chat-mic' : 'chat-send'),
                  tooltip: l(showMic ? 'chatTapRecord' : 'send'),
                  onPressed: enabled && (hasText || showMic)
                      ? (showMic ? onRecord : onSend)
                      : null,
                  icon: showMic ? Icons.mic_none_rounded : Icons.send_rounded,
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _voiceBar(BuildContext context) {
    final preparing = voice.stage == VoiceStage.preparing;
    final ready = voice.stage == VoiceStage.ready;
    final enabled = writable && !busy && !voice.working && !preparing;
    final seconds = voice.duration.inSeconds;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Row(
            children: [
              if (voice.capturing)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.circle, size: 8, color: Color(0xffdf3f5d)),
                ),
              Text(
                '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 19,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: CustomPaint(
                    painter: VoiceWaveformPainter(List.of(voice.samples)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                '60s',
                style: TextStyle(color: Color(0xff838a85), fontSize: 12),
              ),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              key: const Key('chat-voice-delete'),
              tooltip: l('chatDiscardVoice'),
              onPressed: busy ? null : onDiscardVoice,
              icon: const Icon(Icons.delete_outline_rounded, size: 29),
            ),
            if (preparing || voice.working)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                key: const Key('chat-voice-pause'),
                tooltip: l(
                  ready
                      ? (previewingVoice
                            ? 'chatPausePreview'
                            : 'chatPreviewVoice')
                      : (voice.capturing
                            ? 'chatPauseRecording'
                            : 'chatResumeRecording'),
                ),
                onPressed: enabled
                    ? (ready ? onPreviewVoice : onPauseVoice)
                    : null,
                color: const Color(0xffdf3f5d),
                iconSize: 34,
                icon: Icon(
                  ready
                      ? (previewingVoice
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline)
                      : (voice.capturing
                            ? Icons.pause_circle_outline
                            : Icons.mic_none_rounded),
                ),
              ),
            _RoundAction(
              key: const Key('chat-voice-send'),
              tooltip: l('send'),
              onPressed: enabled && voice.duration.inMilliseconds >= 500
                  ? onSendVoice
                  : null,
              icon: Icons.send_rounded,
            ),
          ],
        ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });
  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  @override
  Widget build(BuildContext context) => IconButton.filled(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Theme.of(context).colorScheme.onPrimary,
      disabledBackgroundColor: const Color(0xffd4ddd7),
      minimumSize: const Size(46, 46),
    ),
    icon: Icon(icon, size: 25),
  );
}

class VoiceWaveformPainter extends CustomPainter {
  VoiceWaveformPainter(this.samples);
  final List<double> samples;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff53655c)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5;
    final count = (size.width / 5).floor();
    final start = (samples.length - count).clamp(0, samples.length);
    for (var i = 0; i < count; i++) {
      final index = start + i;
      final amplitude = index < samples.length ? samples[index] : 0.04;
      final height = (size.height * amplitude).clamp(2.0, size.height);
      canvas.drawLine(
        Offset(i * 5 + 2, (size.height - height) / 2),
        Offset(i * 5 + 2, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(VoiceWaveformPainter oldDelegate) => true;
}
