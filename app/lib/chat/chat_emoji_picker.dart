import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'chat_composer.dart';

// Keep a single bilingual search set across app language changes. The picker's
// search helper caches its initial set for the lifetime of the process.
final _chineseNames = {
  for (final category in emojiSetChinese)
    for (final emoji in category.emoji) emoji.emoji: emoji.name,
};
final _bilingualEmoji = [
  for (final category in emojiSetEnglish)
    category.copyWith(
      emoji: [
        for (final emoji in category.emoji)
          emoji.copyWith(
            name: '${emoji.name} | ${_chineseNames[emoji.emoji] ?? ''}',
          ),
      ],
    ),
];
List<CategoryEmoji> _chatEmojiSet(Locale _) => _bilingualEmoji;

/// The server counts Unicode code points, not UTF-16 units or graphemes.
/// Keep insertion atomic so a skin tone or joined emoji is never truncated.
bool insertChatEmoji(
  TextEditingController controller,
  String emoji, {
  TextSelection? selection,
}) {
  final text = controller.text;
  final cursor = selection ?? controller.selection;
  final valid = cursor.isValid && cursor.end <= text.length;
  final start = valid ? cursor.start : text.length;
  final end = valid ? cursor.end : text.length;
  final result = text.replaceRange(start, end, emoji);
  if (result.runes.length > 500) return false;
  controller.value = TextEditingValue(
    text: result,
    selection: TextSelection.collapsed(offset: start + emoji.length),
  );
  return true;
}

class ChatEmojiPickerSheet extends StatelessWidget {
  const ChatEmojiPickerSheet({super.key, required this.l});
  final L l;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height =
        (media.size.height - media.viewInsets.bottom - media.padding.top - 24)
            .clamp(0.0, 380.0);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        l('chatEmoji'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      key: const Key('chat-emoji-close'),
                      tooltip: l('cancel'),
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: EmojiPicker(
                  key: const Key('chat-emoji-picker'),
                  // Handle insertion ourselves to preserve the server's limit.
                  onEmojiSelected: (_, emoji) =>
                      Navigator.pop(context, emoji.emoji),
                  config: Config(
                    height: null,
                    emojiSet: _chatEmojiSet,
                    locale: Locale(l.lang == 'zh' ? 'zh' : 'en'),
                    emojiViewConfig: EmojiViewConfig(
                      columns: (media.size.width / 46).floor().clamp(5, 12),
                      emojiSizeMax: 28,
                      backgroundColor: chatCream,
                      recentsLimit: 28,
                      noRecents: Center(
                        child: Text(
                          l('chatNoRecentEmoji'),
                          style: const TextStyle(
                            color: Color(0xff838a85),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    categoryViewConfig: const CategoryViewConfig(
                      initCategory: Category.SMILEYS,
                      backgroundColor: chatCream,
                      indicatorColor: chatGreen,
                      iconColorSelected: chatGreen,
                      dividerColor: Colors.transparent,
                    ),
                    bottomActionBarConfig: const BottomActionBarConfig(
                      showBackspaceButton: false,
                      backgroundColor: chatCream,
                      buttonColor: chatCream,
                      buttonIconColor: Color(0xff53655c),
                    ),
                    searchViewConfig: SearchViewConfig(
                      backgroundColor: chatCream,
                      buttonIconColor: const Color(0xff53655c),
                      hintText: l('chatSearchEmoji'),
                      inputTextStyle: const TextStyle(fontSize: 16),
                    ),
                    skinToneConfig: const SkinToneConfig(
                      rememberSkinTone: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
