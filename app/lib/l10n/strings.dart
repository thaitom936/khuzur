/// Simple string table for en / mn (Mongolian Cyrillic) / zh.
/// The Mongolian strings are machine-drafted and need a native review.
library;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../settings/settings.dart';

const supportedLangs = ['en', 'mn', 'zh'];

const langNames = {'en': 'English', 'mn': 'Монгол', 'zh': '中文'};

/// Quick-chat phrases, by id. Keep ids stable: they go over the wire.
const chatPhrases = {
  'en': ['Hello!', 'Good move!', 'Hurry up…', 'Ouch!', 'Lucky!', 'Good game', 'Thanks', '😀'],
  'mn': ['Сайн уу!', 'Сайхан нүүдэл!', 'Түргэлээрэй…', 'Өө халаг!', 'Азтай юм!', 'Сайхан тоглолт', 'Баярлалаа', '😀'],
  'zh': ['你好！', '好牌！', '快点吧…', '哎呀！', '真走运！', '打得好', '谢谢', '😀'],
};

const _table = <String, Map<String, String>>{
  'appTitle': {'en': 'Muushig', 'mn': 'Муушиг', 'zh': '慕西格'},
  'play': {'en': 'Single player', 'mn': 'Ганцаараа тоглох', 'zh': '单机模式'},
  'online': {'en': 'Play online', 'mn': 'Онлайн тоглох', 'zh': '在线对战'},
  'settings': {'en': 'Settings', 'mn': 'Тохиргоо', 'zh': '设置'},
  'back': {'en': 'Back', 'mn': 'Буцах', 'zh': '返回'},
  'connecting': {'en': 'Connecting…', 'mn': 'Холбогдож байна…', 'zh': '连接中…'},
  'reconnecting': {'en': 'Reconnecting…', 'mn': 'Дахин холбогдож байна…', 'zh': '重连中…'},
  'quickMatch': {'en': 'Quick match', 'mn': 'Хурдан тоглолт', 'zh': '快速匹配'},
  'resumeGame': {'en': 'Return to game', 'mn': 'Тоглолт руу буцах', 'zh': '返回牌局'},
  'createRoom': {'en': 'Create room', 'mn': 'Өрөө үүсгэх', 'zh': '创建房间'},
  'joinRoom': {'en': 'Join room', 'mn': 'Өрөөнд орох', 'zh': '加入房间'},
  'leaderboard': {'en': 'Leaderboard', 'mn': 'Шилдэг тоглогчид', 'zh': '排行榜'},
  'roomCode': {'en': 'Room code', 'mn': 'Өрөөний код', 'zh': '房间号'},
  'join': {'en': 'Join', 'mn': 'Орох', 'zh': '加入'},
  'cancel': {'en': 'Cancel', 'mn': 'Болих', 'zh': '取消'},
  'searching': {'en': 'Looking for players…', 'mn': 'Тоглогч хайж байна…', 'zh': '正在寻找玩家…'},
  'waitingFriends': {'en': 'Waiting for friends…', 'mn': 'Найзуудыг хүлээж байна…', 'zh': '等待好友加入…'},
  'startNow': {'en': 'Start with bots', 'mn': 'Ботуудтай эхлэх', 'zh': '补充机器人开始'},
  'players': {'en': 'Players', 'mn': 'Тоглогчид', 'zh': '玩家人数'},
  'yourName': {'en': 'Your name', 'mn': 'Таны нэр', 'zh': '你的昵称'},
  'language': {'en': 'Language', 'mn': 'Хэл', 'zh': '语言'},
  'games': {'en': 'Games', 'mn': 'Тоглолт', 'zh': '场次'},
  'wins': {'en': 'Wins', 'mn': 'Хожил', 'zh': '胜场'},
  'rank': {'en': 'Rank', 'mn': 'Байр', 'zh': '名次'},
  'you': {'en': 'You', 'mn': 'Та', 'zh': '你'},
  'bot': {'en': 'Bot', 'mn': 'Бот', 'zh': '电脑'},
  'round': {'en': 'Round', 'mn': 'Үе', 'zh': '局'},
  'trump': {'en': 'Trump', 'mn': 'Хөзөр', 'zh': '主牌'},
  'stock': {'en': 'Stock', 'mn': 'Нөөц', 'zh': '牌堆'},
  'playBtn': {'en': 'Play', 'mn': 'Тоглоно', 'zh': '打'},
  'passBtn': {'en': 'Pass', 'mn': 'Өнжинө', 'zh': '弃'},
  'keepAll': {'en': 'Keep all', 'mn': 'Солихгүй', 'zh': '不换牌'},
  'exchangeN': {'en': 'Exchange', 'mn': 'Солих', 'zh': '换'},
  'decideHint': {'en': 'Play this round, or pass?', 'mn': 'Энэ үед тоглох уу, өнжих үү?', 'zh': '这局打还是弃？'},
  'exchangeHint': {'en': 'Select cards to exchange (up to %d)', 'mn': 'Солих хөзрөө сонго (дээд тал нь %d)', 'zh': '选择要换的牌（最多 %d 张）'},
  'yourTurn': {'en': 'Your turn', 'mn': 'Таны ээлж', 'zh': '轮到你了'},
  'playHint': {'en': 'Tap a card, tap again to play it', 'mn': 'Хөзрөө товшоод, дахин товшиж тогло', 'zh': '点选卡牌，再点一次出牌'},
  'thinking': {'en': '%s is thinking…', 'mn': '%s бодож байна…', 'zh': '%s 思考中…'},
  'takesTrick': {'en': '%s takes the trick', 'mn': '%s гэр авлаа', 'zh': '%s 赢下这一墩'},
  'passed': {'en': 'passed', 'mn': 'өнжсөн', 'zh': '已弃'},
  'tricksN': {'en': 'tricks', 'mn': 'гэр', 'zh': '墩'},
  'score': {'en': 'score', 'mn': 'оноо', 'zh': '分'},
  'roundFinished': {'en': 'Round %d finished', 'mn': '%d-р үе дууслаа', 'zh': '第 %d 局结束'},
  'nextRound': {'en': 'Next round', 'mn': 'Дараагийн үе', 'zh': '下一局'},
  'nextRoundSoon': {'en': 'Next round starting…', 'mn': 'Дараагийн үе эхэлж байна…', 'zh': '下一局即将开始…'},
  'youWin': {'en': 'You win!', 'mn': 'Та хожлоо!', 'zh': '你赢了！'},
  'gameOver': {'en': 'Game over', 'mn': 'Тоглолт дууслаа', 'zh': '游戏结束'},
  'winner': {'en': 'Winner', 'mn': 'Ялагч', 'zh': '赢家'},
  'backToMenu': {'en': 'Back to menu', 'mn': 'Цэс рүү буцах', 'zh': '返回主菜单'},
  'autoOn': {'en': 'Auto-play is on', 'mn': 'Автомат тоглолт асаалттай', 'zh': '已进入托管'},
  'autoOff': {'en': 'Resume control', 'mn': 'Өөрөө тоглох', 'zh': '取消托管'},
  'offline': {'en': 'offline', 'mn': 'холбогдоогүй', 'zh': '离线'},
  'kicked': {'en': 'Signed in from another device', 'mn': 'Өөр төхөөрөмжөөс нэвтэрсэн байна', 'zh': '账号在其他设备登录'},
  'serverUrl': {'en': 'Server address', 'mn': 'Серверийн хаяг', 'zh': '服务器地址'},
  'error_room_not_found': {'en': 'Room not found', 'mn': 'Өрөө олдсонгүй', 'zh': '房间不存在'},
  'error_room_full': {'en': 'Room is full', 'mn': 'Өрөө дүүрсэн байна', 'zh': '房间已满'},
  'error_offline': {'en': 'No connection', 'mn': 'Холболт алга', 'zh': '没有网络连接'},
  'error_generic': {'en': 'Something went wrong', 'mn': 'Алдаа гарлаа', 'zh': '出错了'},
};

class L {
  final String lang;

  const L(this.lang);

  String call(String key) {
    final entry = _table[key];
    return entry?[lang] ?? entry?['en'] ?? key;
  }

  String fmt(String key, Object arg) =>
      call(key).replaceFirst(RegExp('%[ds]'), '$arg');

  String error(String code) {
    final key = 'error_$code';
    return _table.containsKey(key) ? call(key) : call('error_generic');
  }

  List<String> get phrases => chatPhrases[lang] ?? chatPhrases['en']!;

  static L of(BuildContext context) =>
      L(context.watch<SettingsController>().lang.value);
}
