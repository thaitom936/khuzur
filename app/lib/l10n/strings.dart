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
  'en': [
    'Hello!',
    'Good move!',
    'Hurry up…',
    'Ouch!',
    'Lucky!',
    'Good game',
    'Thanks',
    '😀',
  ],
  'mn': [
    'Сайн уу!',
    'Сайхан нүүдэл!',
    'Түргэлээрэй…',
    'Өө халаг!',
    'Азтай юм!',
    'Сайхан тоглолт',
    'Баярлалаа',
    '😀',
  ],
  'zh': ['你好！', '好牌！', '快点吧…', '哎呀！', '真走运！', '打得好', '谢谢', '😀'],
};

const _table = <String, Map<String, String>>{
  'lobby': {'en': 'Lobby', 'mn': 'Танхим', 'zh': '大厅'},
  'profile': {'en': 'My profile', 'mn': 'Миний мэдээлэл', 'zh': '我的'},
  'connected': {'en': 'Connected · ready to play', 'mn': 'Холбогдсон · тоглоход бэлэн', 'zh': '已连接 · 随时入座'},
  'lobbyTitle': {'en': 'Take a seat.', 'mn': 'Ширээнд суу.', 'zh': '找一桌，开一局'},
  'lobbySubtitle': {'en': 'Good company. A great hand.', 'mn': 'Сайн нөхөд. Сайхан тоглолт.', 'zh': '与牌友相聚，从一手好牌开始'},
  'joinByCode': {'en': 'Enter code', 'mn': 'Код оруулах', 'zh': '输入房号'},
  'allTables': {'en': 'All tables', 'mn': 'Бүх ширээ', 'zh': '全部'},
  'availableTables': {'en': 'Open seats', 'mn': 'Сул суудал', 'zh': '可入座'},
  'waitingStatus': {'en': 'Waiting', 'mn': 'Хүлээж байна', 'zh': '待开局'},
  'playingStatus': {'en': 'Playing', 'mn': 'Тоглож байна', 'zh': '进行中'},
  'practiceTable': {'en': 'Bot practice', 'mn': 'Боттой бэлтгэл', 'zh': '机器人练习桌'},
  'publicTable': {'en': 'Public table', 'mn': 'Нээлттэй ширээ', 'zh': '公开牌桌'},
  'humans': {'en': 'human', 'mn': 'хүн', 'zh': '真人'},
  'bots': {'en': 'bots', 'mn': 'бот', 'zh': '机器人'},
  'seated': {'en': 'seated', 'mn': 'суусан', 'zh': '已入座'},
  'readyToJoin': {'en': 'Join before the first hand', 'mn': 'Эхлэхээс өмнө ороорой', 'zh': '入座后即可开始'},
  'takeSeat': {'en': 'Take a seat', 'mn': 'Суух', 'zh': '入座'},
  'fullTable': {'en': 'Full', 'mn': 'Дүүрсэн', 'zh': '已满'},
  'loadingRooms': {'en': 'Finding tables…', 'mn': 'Ширээ хайж байна…', 'zh': '正在加载牌桌…'},
  'refresh': {'en': 'Refresh tables', 'mn': 'Шинэчлэх', 'zh': '刷新列表'},
  'retry': {'en': 'Retry', 'mn': 'Дахин оролдох', 'zh': '重试'},
  'dismiss': {'en': 'Dismiss', 'mn': 'Хаах', 'zh': '知道了'},
  'connectionFailed': {'en': 'Could not connect. Please try again.', 'mn': 'Холбогдож чадсангүй. Дахин оролдоно уу.', 'zh': '暂时无法连接，请重试。'},
  'connectionHint': {'en': 'You can practise offline while we connect.', 'mn': 'Холбогдох зуур офлайнаар бэлтгэл хийж болно.', 'zh': '连接期间，可以先玩一局单机练习。'},
  'roomsFailed': {'en': 'Could not refresh tables. Please retry.', 'mn': 'Ширээг шинэчилж чадсангүй. Дахин оролдоно уу.', 'zh': '房间列表刷新失败，请重试。'},
  'noMatchingRooms': {'en': 'No tables match this filter yet.', 'mn': 'Тохирох ширээ одоогоор алга.', 'zh': '暂无符合条件的房间'},
  'showAllRooms': {'en': 'Show all tables', 'mn': 'Бүх ширээг харах', 'zh': '查看全部房间'},
  'error_login_failed': {'en': 'Could not sign in. Please reconnect.', 'mn': 'Нэвтэрч чадсангүй. Дахин холбогдоно уу.', 'zh': '登录未成功，请重新连接。'},
  'tableLabel': {'en': 'Table', 'mn': 'Ширээ', 'zh': '牌桌'},
  'chat': {'en': 'Chat', 'mn': 'Чат', 'zh': '聊天'},
  'cardReturned': {'en': 'Card returned to your hand.', 'mn': 'Хөзөр гарт буцлаа.', 'zh': '牌已退回手中。'},
  'error_illegal_card': {'en': 'Follow the required suit or trump.', 'mn': 'Шаардлагатай масть эсвэл козыроор тоглоно уу.', 'zh': '请按跟牌、主牌规则出牌。'},
  'error_not_your_turn': {'en': 'It is no longer your turn.', 'mn': 'Таны ээлж биш байна.', 'zh': '当前已不是你的回合。'},
  'error_wrong_phase': {'en': 'The table has moved to the next phase.', 'mn': 'Тоглолт дараагийн үе шатанд шилжлээ.', 'zh': '牌局已进入下一阶段。'},
  'error_card_not_in_hand': {'en': 'This card is no longer in your hand.', 'mn': 'Энэ хөзөр таны гарт байхгүй байна.', 'zh': '这张牌已不在你的手牌中。'},
  'error_timeout': {'en': 'The request timed out. Please try again.', 'mn': 'Хүсэлтийн хугацаа дууссан. Дахин оролдоно уу.', 'zh': '请求超时，请重试。'},
  'error_disconnected': {'en': 'Connection lost. Reconnecting…', 'mn': 'Холболт тасарлаа. Дахин холбогдож байна…', 'zh': '连接已断开，正在重连…'},
  'error_already_in_room': {'en': 'Return to your current game first.', 'mn': 'Одоогийн тоглолт руугаа буцна уу.', 'zh': '你已在牌局中，请先返回当前牌局。'},
  'appTitle': {'en': 'Muushig', 'mn': 'Муушиг', 'zh': '慕西格'},
  'play': {'en': 'Single player', 'mn': 'Ганцаараа тоглох', 'zh': '单机模式'},
  'online': {'en': 'Play online', 'mn': 'Онлайн тоглох', 'zh': '在线对战'},
  'settings': {'en': 'Settings', 'mn': 'Тохиргоо', 'zh': '设置'},
  'back': {'en': 'Back', 'mn': 'Буцах', 'zh': '返回'},
  'connecting': {'en': 'Connecting…', 'mn': 'Холбогдож байна…', 'zh': '连接中…'},
  'reconnecting': {
    'en': 'Reconnecting…',
    'mn': 'Дахин холбогдож байна…',
    'zh': '重连中…',
  },
  'quickMatch': {'en': 'Quick match', 'mn': 'Хурдан тоглолт', 'zh': '快速匹配'},
  'resumeGame': {
    'en': 'Return to game',
    'mn': 'Тоглолт руу буцах',
    'zh': '返回牌局',
  },
  'createRoom': {'en': 'Create room', 'mn': 'Өрөө үүсгэх', 'zh': '创建房间'},
  'joinRoom': {'en': 'Join room', 'mn': 'Өрөөнд орох', 'zh': '加入房间'},
  'leaderboard': {'en': 'Leaderboard', 'mn': 'Шилдэг тоглогчид', 'zh': '排行榜'},
  'roomCode': {'en': 'Room code', 'mn': 'Өрөөний код', 'zh': '房间号'},
  'join': {'en': 'Join', 'mn': 'Орох', 'zh': '加入'},
  'cancel': {'en': 'Cancel', 'mn': 'Болих', 'zh': '取消'},
  'searching': {
    'en': 'Looking for players…',
    'mn': 'Тоглогч хайж байна…',
    'zh': '正在寻找玩家…',
  },
  'waitingFriends': {
    'en': 'Waiting for friends…',
    'mn': 'Найзуудыг хүлээж байна…',
    'zh': '等待好友加入…',
  },
  'startNow': {
    'en': 'Start with bots',
    'mn': 'Ботуудтай эхлэх',
    'zh': '补充机器人开始',
  },
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
  'decideHint': {
    'en': 'Play this round, or pass?',
    'mn': 'Энэ үед тоглох уу, өнжих үү?',
    'zh': '这局打还是弃？',
  },
  'exchangeHint': {
    'en': 'Select cards to exchange (up to %d)',
    'mn': 'Солих хөзрөө сонго (дээд тал нь %d)',
    'zh': '选择要换的牌（最多 %d 张）',
  },
  'yourTurn': {'en': 'Your turn', 'mn': 'Таны ээлж', 'zh': '轮到你了'},
  'playHint': {
    'en': 'Tap a card to play',
    'mn': 'Хөзрөө товшиж тогло',
    'zh': '点击卡牌即可出牌',
  },
  'thinking': {
    'en': '%s is thinking…',
    'mn': '%s бодож байна…',
    'zh': '%s 思考中…',
  },
  'takesTrick': {
    'en': '%s takes the trick',
    'mn': '%s гэр авлаа',
    'zh': '%s 赢下这一墩',
  },
  'passed': {'en': 'passed', 'mn': 'өнжсөн', 'zh': '已弃'},
  'tricksN': {'en': 'tricks', 'mn': 'гэр', 'zh': '墩'},
  'score': {'en': 'score', 'mn': 'оноо', 'zh': '分'},
  'roundFinished': {
    'en': 'Round %d finished',
    'mn': '%d-р үе дууслаа',
    'zh': '第 %d 局结束',
  },
  'nextRound': {'en': 'Next round', 'mn': 'Дараагийн үе', 'zh': '下一局'},
  'nextRoundSoon': {
    'en': 'Next round starting…',
    'mn': 'Дараагийн үе эхэлж байна…',
    'zh': '下一局即将开始…',
  },
  'youWin': {'en': 'You win!', 'mn': 'Та хожлоо!', 'zh': '你赢了！'},
  'gameOver': {'en': 'Game over', 'mn': 'Тоглолт дууслаа', 'zh': '游戏结束'},
  'winner': {'en': 'Winner', 'mn': 'Ялагч', 'zh': '赢家'},
  'backToMenu': {'en': 'Back to menu', 'mn': 'Цэс рүү буцах', 'zh': '返回主菜单'},
  'autoOn': {
    'en': 'Auto-play is on',
    'mn': 'Автомат тоглолт асаалттай',
    'zh': '已进入托管',
  },
  'autoOff': {'en': 'Resume control', 'mn': 'Өөрөө тоглох', 'zh': '取消托管'},
  'offline': {'en': 'offline', 'mn': 'холбогдоогүй', 'zh': '离线'},
  'kicked': {
    'en': 'Signed in from another device',
    'mn': 'Өөр төхөөрөмжөөс нэвтэрсэн байна',
    'zh': '账号在其他设备登录',
  },
  'serverUrl': {'en': 'Server address', 'mn': 'Серверийн хаяг', 'zh': '服务器地址'},
  'coins': {'en': 'Coins', 'mn': 'Зоос', 'zh': '金币'},
  'watch': {'en': 'Watch', 'mn': 'Үзэх', 'zh': '观战'},
  'rooms': {'en': 'Rooms', 'mn': 'Өрөөнүүд', 'zh': '房间列表'},
  'sit': {'en': 'Sit down', 'mn': 'Суух', 'zh': '坐下'},
  'noSeatAvailable': {'en': 'No free seat', 'mn': 'Сул суудал алга', 'zh': '暂无空位'},
  'error_already_started': {'en': 'This table no longer accepts seats. You can keep watching.', 'mn': 'Суудал авах боломжгүй. Үргэлжлүүлэн үзэж болно.', 'zh': '当前牌桌暂不可入座，可以继续观战。'},
  'inProgress': {'en': 'Round %s', 'mn': '%s-р үе', 'zh': '第 %s 局'},
  'noRooms': {
    'en': 'No open tables',
    'mn': 'Нээлттэй ширээ алга',
    'zh': '暂无房间',
  },
  'lockedRoom': {'en': 'Private room', 'mn': 'Хаалттай өрөө', 'zh': '私密房间'},
  'lockedHint': {
    'en': 'Hidden from the lobby; join by code or invite',
    'mn': 'Жагсаалтад харагдахгүй; код эсвэл урилгаар орно',
    'zh': '不在大厅显示，仅凭房号或邀请加入',
  },
  'spectating': {'en': 'Spectating', 'mn': 'Үзэж байна', 'zh': '观战中'},
  'replays': {'en': 'Replays', 'mn': 'Бичлэгүүд', 'zh': '对局回放'},
  'noReplays': {
    'en': 'No replays yet',
    'mn': 'Одоогоор бичлэг алга',
    'zh': '暂无回放',
  },
  'dailyTitle': {'en': 'Daily rewards', 'mn': 'Өдрийн шагнал', 'zh': '每日奖励'},
  'dailyBonus': {'en': 'Daily bonus', 'mn': 'Өдрийн урамшуулал', 'zh': '每日签到'},
  'claim': {'en': 'Claim', 'mn': 'Авах', 'zh': '领取'},
  'claimed': {'en': 'Claimed', 'mn': 'Авсан', 'zh': '已领取'},
  'task_play3': {
    'en': 'Play 3 games',
    'mn': '3 тоглолт тоглох',
    'zh': '完成 3 场对局',
  },
  'task_win1': {'en': 'Win a game', 'mn': '1 тоглолт хожих', 'zh': '赢下 1 场对局'},
  'task_tricks10': {
    'en': 'Take 10 tricks',
    'mn': '10 гэр авах',
    'zh': '赢下 10 墩',
  },
  'friends': {'en': 'Friends', 'mn': 'Найзууд', 'zh': '好友'},
  'addFriend': {
    'en': 'Add friend (name or ID)',
    'mn': 'Найз нэмэх (нэр эсвэл ID)',
    'zh': '添加好友（昵称或 ID）',
  },
  'add': {'en': 'Add', 'mn': 'Нэмэх', 'zh': '添加'},
  'requests': {'en': 'Requests', 'mn': 'Хүсэлтүүд', 'zh': '好友申请'},
  'accept': {'en': 'Accept', 'mn': 'Зөвшөөрөх', 'zh': '同意'},
  'decline': {'en': 'Decline', 'mn': 'Татгалзах', 'zh': '拒绝'},
  'requestSent': {
    'en': 'Request sent',
    'mn': 'Хүсэлт илгээгдлээ',
    'zh': '申请已发送',
  },
  'invite': {'en': 'Invite', 'mn': 'Урих', 'zh': '邀请'},
  'inviteFriends': {'en': 'Invite friends', 'mn': 'Найзаа урих', 'zh': '邀请好友'},
  'inviteFrom': {
    'en': '%s invites you to play',
    'mn': '%s таныг тоглохыг урьж байна',
    'zh': '%s 邀请你加入牌局',
  },
  'stake': {'en': 'Stake', 'mn': 'Бооцоо', 'zh': '门票'},
  'casual': {'en': 'Free', 'mn': 'Үнэгүй', 'zh': '免费场'},
  'wonCoins': {'en': '+%s coins', 'mn': '+%s зоос', 'zh': '+%s 金币'},
  'error_insufficient': {
    'en': 'Not enough coins',
    'mn': 'Зоос хүрэлцэхгүй байна',
    'zh': '金币不足',
  },
  'error_friend_offline': {
    'en': 'Friend is offline',
    'mn': 'Найз тань холбогдоогүй байна',
    'zh': '好友不在线',
  },
  'error_already_friends': {
    'en': 'Already friends',
    'mn': 'Аль хэдийн найзууд',
    'zh': '已经是好友',
  },
  'error_already_requested': {
    'en': 'Request already sent',
    'mn': 'Хүсэлт илгээгдсэн байна',
    'zh': '已发送过申请',
  },
  'error_no_user': {
    'en': 'Player not found',
    'mn': 'Тоглогч олдсонгүй',
    'zh': '找不到该玩家',
  },
  'error_room_not_found': {
    'en': 'Room not found',
    'mn': 'Өрөө олдсонгүй',
    'zh': '房间不存在',
  },
  'error_room_full': {
    'en': 'Room is full',
    'mn': 'Өрөө дүүрсэн байна',
    'zh': '房间已满',
  },
  'error_offline': {
    'en': 'No connection',
    'mn': 'Холболт алга',
    'zh': '没有网络连接',
  },
  'error_generic': {
    'en': 'Something went wrong',
    'mn': 'Алдаа гарлаа',
    'zh': '出错了',
  },
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
