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
  'roomCodeInvalid': {
    'en': 'Enter a 6-digit room code',
    'mn': '6 оронтой өрөөний код оруулна уу',
    'zh': '请输入 6 位房间号',
  },
  'copy': {'en': 'Copy', 'mn': 'Хуулах', 'zh': '复制'},
  'createAndEnter': {
    'en': 'Create and enter',
    'mn': 'Үүсгээд орох',
    'zh': '创建并进入',
  },
  'roomVisibility': {
    'en': 'Who can see the room',
    'mn': 'Өрөөний харагдах байдал',
    'zh': '房间可见性',
  },
  'publicRoom': {'en': 'Public', 'mn': 'Нээлттэй', 'zh': '公开'},
  'inviteRoom': {'en': 'Invite only', 'mn': 'Зөвхөн урилгаар', 'zh': '仅邀请'},
  'publicRoomHint': {
    'en': 'Listed in the lobby. Players enter as spectators first.',
    'mn': 'Лоббид харагдана. Эхлээд үзэгчээр орно.',
    'zh': '显示在大厅，进桌后默认观战。',
  },
  'returnTable': {
    'en': 'Return to table',
    'mn': 'Ширээнд буцах',
    'zh': '返回进行中的牌桌',
  },
  'clubInviteOnly': {
    'en': 'Clubs can only be joined by invitation.',
    'mn': 'Клубт зөвхөн урилгаар элсэж болно.',
    'zh': '仅通过邀请加入俱乐部',
  },
  'clubNoMembership': {
    'en': 'You have not joined a club',
    'mn': 'Та клубт элсээгүй байна',
    'zh': '尚未加入俱乐部',
  },
  'clubInvitation': {
    'en': 'Club invitation',
    'mn': 'Клубын урилга',
    'zh': '俱乐部邀请',
  },
  'clubEnterInvite': {
    'en': 'Enter invitation code',
    'mn': 'Урилгын код оруулах',
    'zh': '输入邀请码',
  },
  'clubInviteCode': {'en': 'Invitation code', 'mn': 'Урилгын код', 'zh': '邀请码'},
  'clubInviteCreate': {
    'en': 'Invite friends',
    'mn': 'Найзуудаа урих',
    'zh': '邀请好友',
  },
  'clubInvitePreview': {
    'en': 'View invitation',
    'mn': 'Урилга харах',
    'zh': '查看邀请',
  },
  'clubInviteFrom': {'en': 'Invited by %s', 'mn': '%s урьсан', 'zh': '邀请人：%s'},
  'clubInviteConfirm': {
    'en': 'Confirm and join',
    'mn': 'Баталгаажуулж элсэх',
    'zh': '确认加入',
  },
  'clubInviteCopied': {
    'en': 'Invitation code copied',
    'mn': 'Урилгын кодыг хууллаа',
    'zh': '邀请码已复制',
  },
  'clubInviteExpiry': {
    'en': 'Expires: %s',
    'mn': 'Дуусах хугацаа: %s',
    'zh': '有效期至：%s',
  },
  'clubInviteHint': {
    'en': 'Ask a friend for an invitation or create your own club.',
    'mn': 'Найзаасаа урилга авах эсвэл клуб үүсгэнэ үү.',
    'zh': '请好友发送邀请，或创建自己的俱乐部。',
  },
  'error_club_invite_required': {
    'en': 'A valid invitation is required',
    'mn': 'Хүчинтэй урилга шаардлагатай',
    'zh': '需要有效邀请才能加入',
  },
  'error_club_invite_expired': {
    'en': 'Invitation expired or invalid. Ask the owner for a new one.',
    'mn': 'Урилга хүчингүй эсвэл хугацаа дууссан. Шинэ урилга авна уу.',
    'zh': '邀请已失效，请联系群主重新发送',
  },

  "clubs": {"en": "Clubs", "mn": "Клубууд", "zh": "俱乐部"},
  "lobbyChat": {"en": "Lobby chat", "mn": "Лобби чат", "zh": "大厅聊天"},
  "tableChat": {"en": "Table chat", "mn": "Ширээний чат", "zh": "牌桌聊天"},
  "send": {"en": "Send", "mn": "Илгээх", "zh": "发送"},
  "chatOlder": {
    "en": "Load earlier messages",
    "mn": "Өмнөх зурвасууд",
    "zh": "加载更早消息",
  },
  "chatPlaceholder": {
    "en": "Write a message…",
    "mn": "Зурвас бичих…",
    "zh": "输入消息…",
  },
  "chatReadOnly": {"en": "Read only", "mn": "Зөвхөн унших", "zh": "当前只能阅读"},
  "chatClosed": {
    "en": "This channel is closed or your access has ended",
    "mn": "Чат хаагдсан",
    "zh": "频道已关闭或已失去访问权限",
  },
  "chatSending": {"en": "Sending…", "mn": "Илгээж байна…", "zh": "发送中…"},
  "chatDeleted": {
    "en": "Message deleted",
    "mn": "Зурвас устгагдсан",
    "zh": "消息已删除",
  },
  "chatUploading": {"en": "Uploading…", "mn": "Байршуулж байна…", "zh": "上传中…"},
  "chatVerifying": {
    "en": "Checking file…",
    "mn": "Файл шалгаж байна…",
    "zh": "正在校验文件…",
  },
  "chatRetryUpload": {
    "en": "Retry upload",
    "mn": "Дахин байршуулах",
    "zh": "重试上传",
  },
  "chatAttachment": {"en": "Attachment", "mn": "Хавсралт", "zh": "附件"},
  "chatEmoji": {"en": "Emoji", "mn": "Эможи", "zh": "表情"},
  "chatSearchEmoji": {
    "en": "Search emoji",
    "mn": "Эможи хайх (English)",
    "zh": "搜索表情",
  },
  "chatNoRecentEmoji": {
    "en": "Your recent emoji will appear here",
    "mn": "Сүүлд ашигласан эможи энд харагдана",
    "zh": "使用过的表情会显示在这里",
  },
  "chatImage": {"en": "Image", "mn": "Зураг", "zh": "图片"},
  "chatCamera": {"en": "Take photo", "mn": "Зураг авах", "zh": "拍照"},
  "chatVideo": {"en": "Video", "mn": "Видео", "zh": "视频"},
  "chatRecordVideo": {"en": "Record video", "mn": "Видео бичих", "zh": "拍摄视频"},
  "chatVoice": {"en": "Voice", "mn": "Дуу", "zh": "语音"},
  "chatPhotosVideos": {
    "en": "Photos and videos",
    "mn": "Зураг ба видео",
    "zh": "图片和视频",
  },
  "chatPhoto": {"en": "Photo", "mn": "Зураг", "zh": "照片"},
  "chatTapRecord": {
    "en": "Record voice message",
    "mn": "Дуут зурвас бичих",
    "zh": "录制语音消息",
  },
  "chatDiscardVoice": {
    "en": "Discard recording",
    "mn": "Бичлэг устгах",
    "zh": "删除录音",
  },
  "chatPauseRecording": {
    "en": "Pause recording",
    "mn": "Бичлэг түр зогсоох",
    "zh": "暂停录音",
  },
  "chatResumeRecording": {
    "en": "Resume recording",
    "mn": "Бичлэг үргэлжлүүлэх",
    "zh": "继续录音",
  },
  "chatStopRecording": {
    "en": "Stop recording",
    "mn": "Бичлэг зогсоох",
    "zh": "结束录制",
  },
  "chatPreviewVoice": {
    "en": "Listen to recording",
    "mn": "Бичлэг сонсох",
    "zh": "试听录音",
  },
  "chatPausePreview": {
    "en": "Pause playback",
    "mn": "Тоглуулахыг түр зогсоох",
    "zh": "暂停播放",
  },
  "chatPlayVideo": {"en": "Play video", "mn": "Видео тоглуулах", "zh": "播放视频"},
  "chatPreview": {"en": "Preview", "mn": "Урьдчилан харах", "zh": "预览"},
  "chatPreviewHint": {
    "en": "Send to this chat",
    "mn": "Энэ чатад илгээх",
    "zh": "发送到当前聊天",
  },
  "chatCameraUnavailable": {
    "en": "Camera unavailable. Check camera permission and try again.",
    "mn": "Камер ашиглах боломжгүй. Камерын эрхийг шалгана уу.",
    "zh": "相机暂不可用，请检查相机权限后重试",
  },
  "chatFlash": {"en": "Flash", "mn": "Гэрэл", "zh": "闪光灯"},
  "chatFlashUnavailable": {
    "en": "Flash is unavailable for this camera",
    "mn": "Энэ камер гэрэлгүй",
    "zh": "当前镜头不支持此闪光灯模式",
  },
  "chatFlipCamera": {"en": "Switch camera", "mn": "Камер солих", "zh": "切换镜头"},
  "chatHoldRecord": {
    "en": "Hold to record",
    "mn": "Дарж бичлэг хийх",
    "zh": "按住录音",
  },
  "chatRecording": {
    "en": "Recording · slide up to cancel · max 60s",
    "mn": "Бичлэг хийж байна · дээш гулсуулж цуцлах",
    "zh": "录音中 · 上滑取消 · 最长 60 秒",
  },
  "chatRecordingCancel": {
    "en": "Release to cancel",
    "mn": "Тавьж цуцлах",
    "zh": "松开取消录音",
  },
  "chatRecovered": {
    "en": "Send recovered file to this chat?",
    "mn": "Сэргээсэн файлыг энэ чатад илгээх үү?",
    "zh": "是否将恢复的文件发送到当前聊天？",
  },
  "chatDelete": {"en": "Delete message", "mn": "Зурвас устгах", "zh": "删除消息"},
  "chatReport": {"en": "Report", "mn": "Мэдэгдэх", "zh": "举报"},
  "chatBlock": {"en": "Block sender", "mn": "Илгээгчийг хаах", "zh": "屏蔽发送者"},
  "chatMute": {
    "en": "Mute for 1 hour",
    "mn": "1 цаг дуугүй болгох",
    "zh": "禁言 1 小时",
  },
  "mediaExpired": {
    "en": "File expired (kept for 7 days)",
    "mn": "Файлын хугацаа дууссан (7 хоног)",
    "zh": "文件已过期（保留 7 天）",
  },
  "clubCreate": {"en": "Create club", "mn": "Клуб үүсгэх", "zh": "创建俱乐部"},
  "clubName": {"en": "Club name", "mn": "Клубын нэр", "zh": "俱乐部名称"},
  "clubDescription": {
    "en": "About / announcement",
    "mn": "Танилцуулга / зарлал",
    "zh": "简介／公告",
  },
  "clubMembers": {"en": "members", "mn": "гишүүд", "zh": "位成员"},
  "clubMine": {"en": "My club", "mn": "Миний клуб", "zh": "我的俱乐部"},
  "clubSearch": {"en": "Find a club", "mn": "Клуб хайх", "zh": "搜索俱乐部"},
  "clubEmpty": {"en": "No clubs yet", "mn": "Клуб байхгүй", "zh": "暂无俱乐部"},
  "clubOwner": {"en": "Owner", "mn": "Эзэн", "zh": "会长"},
  "clubChat": {"en": "Club chat", "mn": "Клубын чат", "zh": "俱乐部聊天"},
  "clubJoin": {"en": "Join club", "mn": "Клубт нэгдэх", "zh": "加入俱乐部"},
  "clubLeave": {"en": "Leave club", "mn": "Клубээс гарах", "zh": "退出俱乐部"},
  "clubLeaveHint": {
    "en":
        "Leave this club? Owners must transfer ownership first if other members remain.",
    "mn": "Клубээс гарах уу?",
    "zh": "确定退出？有其他成员时，会长需先转让会长身份。",
  },
  "clubTransfer": {
    "en": "Transfer ownership",
    "mn": "Эзэмшил шилжүүлэх",
    "zh": "转让会长",
  },
  "clubKick": {"en": "Remove member", "mn": "Гишүүн хасах", "zh": "移除成员"},
  "error_chat_forbidden": {
    "en": "You cannot access this chat",
    "mn": "Танд энэ чатын эрх байхгүй",
    "zh": "没有该频道的访问权限",
  },
  "error_chat_read_only": {
    "en": "Spectators can read only",
    "mn": "Үзэгч зөвхөн уншина",
    "zh": "观战者只能阅读",
  },
  "error_chat_muted": {
    "en": "You are muted in this channel",
    "mn": "Та энэ чатад дуугүй болсон",
    "zh": "你在该频道被禁言",
  },
  "error_chat_rate_limit": {
    "en": "Please wait before trying again",
    "mn": "Түр хүлээнэ үү",
    "zh": "操作过于频繁，请稍后再试",
  },
  "error_chat_bad_message": {
    "en": "Message is empty or too long",
    "mn": "Зурвас хоосон эсвэл хэт урт",
    "zh": "消息为空或超过 500 字",
  },
  "error_chat_text_only": {
    "en": "This channel supports text and emoji only",
    "mn": "Энэ чат зөвхөн текст ба эможи дэмжинэ",
    "zh": "该频道只支持文字和表情",
  },
  "error_chat_unavailable": {
    "en": "Chat storage is unavailable",
    "mn": "Чат боломжгүй байна",
    "zh": "聊天存储暂不可用",
  },
  "error_chat_database_failed": {
    "en": "Could not save, please retry",
    "mn": "Хадгалж чадсангүй",
    "zh": "保存失败，请重试",
  },
  "error_club_not_member": {
    "en": "Join the club first",
    "mn": "Эхлээд клубт нэгдэнэ үү",
    "zh": "请先加入该俱乐部",
  },
  "error_club_not_found": {
    "en": "Club is closed or unavailable",
    "mn": "Клуб олдсонгүй",
    "zh": "俱乐部已关闭或不存在",
  },
  "error_club_already_joined": {
    "en": "You can belong to only one club",
    "mn": "Зөвхөн нэг клубт нэгдэнэ",
    "zh": "同一时间只能加入一个俱乐部",
  },
  "error_club_transfer_first": {
    "en": "Transfer ownership before leaving",
    "mn": "Эзэмшлээ эхлээд шилжүүлнэ үү",
    "zh": "请先转让会长身份，再退出",
  },
  "error_club_full": {
    "en": "Club is full (200 members)",
    "mn": "Клуб дүүрсэн",
    "zh": "俱乐部已满（200 人）",
  },
  "error_club_bad_name": {
    "en": "Enter a name of 1–40 characters",
    "mn": "1–40 тэмдэгт нэр оруулна уу",
    "zh": "名称需 1～40 字，简介不超过 300 字",
  },
  "error_media_unavailable": {
    "en": "Media storage has not been configured yet",
    "mn": "Медиа хадгалалт тохируулаагүй",
    "zh": "媒体存储尚未配置，暂时可发送文字",
  },
  "error_media_bad_file": {
    "en": "Unsupported or damaged file",
    "mn": "Файл гэмтсэн эсвэл дэмжихгүй",
    "zh": "文件格式不支持或已损坏",
  },
  "error_media_too_large": {
    "en": "Image ≤5 MB, voice ≤2 MB, video ≤20 MB",
    "mn": "Файл хэт том",
    "zh": "图片≤5 MB、语音≤2 MB、视频≤20 MB",
  },
  "error_media_bad_duration": {
    "en": "Voice and video must be within 60 seconds",
    "mn": "60 секундээс хэтрэхгүй",
    "zh": "语音和视频必须在 60 秒以内",
  },
  "error_media_storage_failed": {
    "en": "Upload failed; try again",
    "mn": "Байршуулахад алдаа гарлаа",
    "zh": "上传失败，请重试",
  },
  "error_media_expired": {
    "en": "File has expired",
    "mn": "Файлын хугацаа дууссан",
    "zh": "文件已过期",
  },
  "error_media_processing_unavailable": {
    "en": "Media processing is unavailable",
    "mn": "Медиа боловсруулах боломжгүй",
    "zh": "媒体处理服务暂不可用",
  },
  "error_media_not_ready": {
    "en": "Wait for the upload to finish",
    "mn": "Байршуулахыг хүлээнэ үү",
    "zh": "请等待上传及校验完成",
  },
  "error_chat_capture_busy": {
    "en": "Turn off your live microphone/camera before recording",
    "mn": "Шууд микрофон/камерыг эхлээд унтраана уу",
    "zh": "请先关闭牌桌实时麦克风／摄像头，再录制消息",
  },
  "error_chat_mic_denied": {
    "en": "Microphone permission is required",
    "mn": "Микрофоны эрх шаардлагатай",
    "zh": "请允许麦克风权限",
  },

  "thousandFriendHint": {
    "en": "3 friends · host starts · first to 1000 wins",
    "mn": "3 найз · эзэн эхлүүлнэ · 1000 оноо",
    "zh": "三人好友局 · 房主开局 · 先达 1000 分获胜",
  },
  "thousandBidHint": {
    "en": "Bid or pass",
    "mn": "Оноо зарлах эсвэл өнжих",
    "zh": "轮流叫分或放弃叫分",
  },
  "thousandGiveHint": {
    "en": "Select two cards in recipient order",
    "mn": "Хоёр хөзөр сонгоно уу",
    "zh": "按接收者顺序选择两张牌，各送一张",
  },
  "thousandContractHint": {
    "en": "Confirm or raise your contract",
    "mn": "Захиалгаа батлах",
    "zh": "确认最终叫分，可以加叫",
  },
  "thousandContract": {"en": "Contract", "mn": "Захиалга", "zh": "叫分"},
  "thousandNoTrump": {
    "en": "No trump yet",
    "mn": "Козырь хараахан байхгүй",
    "zh": "尚无主牌",
  },
  "thousandPoints": {
    "en": "Card points + marriage",
    "mn": "Хөзрийн оноо + хос",
    "zh": "牌点＋报对分",
  },
  "thousandBarrel": {"en": "Barrel", "mn": "Торх", "zh": "上桶"},
  "thousandBid": {"en": "Bid", "mn": "Зарлах", "zh": "叫分"},
  "thousandConfirm": {"en": "Confirm", "mn": "Батлах", "zh": "确认"},
  "thousandGive": {"en": "Give cards", "mn": "Хөзөр өгөх", "zh": "分牌"},
  "thousandAnnounce": {"en": "Declare K+Q", "mn": "K+Q зарлах", "zh": "报对出牌"},
  "error_thousand_need_players": {
    "en": "Exactly 3 players required",
    "mn": "Яг 3 тоглогч шаардлагатай",
    "zh": "需要三位玩家才能开局",
  },
  "error_thousand_bad_bid": {
    "en": "Invalid bid or contract",
    "mn": "Захиалгын оноо буруу",
    "zh": "叫分必须符合下限、5 分步长及报对上限",
  },
  "error_thousand_give_two": {
    "en": "Select exactly two cards",
    "mn": "Яг хоёр хөзөр сонго",
    "zh": "请选择两张牌，各给另外一位玩家",
  },
  "error_thousand_follow_suit": {
    "en": "Follow suit, or trump if void",
    "mn": "Ижил өнгө эсвэл козырь тогло",
    "zh": "有同花必须跟；缺门有主必须出主牌",
  },
  "error_thousand_bad_marriage": {
    "en": "Win a trick before declaring held K+Q",
    "mn": "Нэг гараа хожоод K+Q зарлана",
    "zh": "需先赢过一墩，领出时持同花 K、Q 才能报对",
  },

  'durakDeck': {'en': 'Deck size', 'mn': 'Хөзрийн тоо', 'zh': '牌组张数'},
  'durakTransferMode': {
    'en': 'Transfer mode',
    'mn': 'Шилжүүлэх горим',
    'zh': '转移模式',
  },
  'durakAllowDraw': {
    'en': 'Allow final draw',
    'mn': 'Тэнцэх боломжтой',
    'zh': '允许末轮平局',
  },
  'durakFriendHint': {
    'en': 'Private friends · host starts · no entry fee',
    'mn': 'Найзын өрөө · эзэн эхлүүлнэ · төлбөргүй',
    'zh': '好友私密房 · 房主开局 · 打牌不扣金币',
  },
  'durakOut': {'en': 'Finished', 'mn': 'Дууссан', 'zh': '已出完'},
  'durakDraw': {'en': 'Draw', 'mn': 'Тэнцээ', 'zh': '平局'},
  'durakChooseTarget': {
    'en': 'Choose an attack card, then cover it',
    'mn': 'Довтлох хөзрийг сонгоод дарна уу',
    'zh': '点击攻击牌选择目标，再选择盖牌',
  },
  'durakAddHint': {
    'en': 'Add matching ranks or finish',
    'mn': 'Ижил тоо нэмэх эсвэл дуусгах',
    'zh': '追加桌面已有点数的牌，或结束追加',
  },
  'durakAttackHint': {
    'en': 'Attack with one rank',
    'mn': 'Ижил тоотой хөзрөөр довтлох',
    'zh': '选择同点数手牌发起攻击',
  },
  'durakTaking': {
    'en': 'Defender is taking',
    'mn': 'Хамгаалагч авч байна',
    'zh': '防守者收牌中',
  },
  'durakTransfer': {'en': 'Transfer', 'mn': 'Шилжүүлэх', 'zh': '转移'},
  'durakTake': {'en': 'Take', 'mn': 'Авах', 'zh': '收牌'},
  'durakFinish': {'en': 'Done', 'mn': 'Дуусгах', 'zh': '结束追加'},
  'durakDefend': {'en': 'Cover', 'mn': 'Дарах', 'zh': '盖牌'},
  'error_durak_bad_cards': {
    'en': 'Invalid card selection',
    'mn': 'Хөзрийн сонголт буруу',
    'zh': '所选手牌无效或重复',
  },
  'error_durak_bad_deck': {
    'en': 'Choose 24, 36 or 52 cards',
    'mn': '24, 36 эсвэл 52 хөзөр сонгоно уу',
    'zh': '请选择 24、36 或 52 张牌',
  },
  'error_durak_rank': {
    'en': 'Use ranks already on the table',
    'mn': 'Ширээн дээрх тоотой хөзөр сонгоно уу',
    'zh': '首攻须同点数，追加须使用桌面已有点数',
  },
  'error_durak_attack_limit': {
    'en': 'Too many attacking cards',
    'mn': 'Довтлох хөзөр хэт олон',
    'zh': '超过本轮攻击张数或防守手牌上限',
  },
  'error_durak_target': {
    'en': 'Choose an uncovered attack card',
    'mn': 'Дараагүй довтлох хөзрийг сонгоно уу',
    'zh': '请选择一张尚未盖住的攻击牌',
  },
  'error_durak_cannot_beat': {
    'en': 'Use a higher card of the same suit or a trump',
    'mn': 'Ижил мастийн том хөзөр эсвэл козырь ашиглана уу',
    'zh': '需要同花色更大的牌，或符合规则的主牌',
  },
  'error_durak_transfer': {
    'en': 'Transfer is unavailable after covering',
    'mn': 'Дарсны дараа шилжүүлэх боломжгүй',
    'zh': '需要同点数转移牌，且开始盖牌后不能转移',
  },
  'error_durak_transfer_limit': {
    'en': 'The next defender cannot take this many attacks',
    'mn': 'Дараагийн хамгаалагчийн хөзөр хүрэлцэхгүй',
    'zh': '转移后超过下一位防守者手牌数或攻击上限',
  },
  'error_durak_cannot_finish': {
    'en': 'You must attack or defend',
    'mn': 'Довтлох эсвэл хамгаалах хэрэгтэй',
    'zh': '当前需要攻击或防守，不能结束追加',
  },
  'm13Opening': {
    'en': 'First play must include',
    'mn': 'Эхний нүүдэлд оруулах хөзөр',
    'zh': '首手必须包含',
  },
  'm13Select': {
    'en': 'Select cards, then Play',
    'mn': 'Хөзрөө сонгоод гаргана уу',
    'zh': '选择手牌后点击出牌',
  },
  'm13Hint': {'en': 'Hint', 'mn': 'Санал', 'zh': '提示'},
  'm13Pass': {'en': 'Pass', 'mn': 'Өнжих', 'zh': '过'},
  'm13Play': {'en': 'Play', 'mn': 'Гаргах', 'zh': '出牌'},
  'm13Remaining': {'en': 'Cards', 'mn': 'Хөзөр', 'zh': '剩牌'},
  'm13Start': {'en': 'Start game', 'mn': 'Эхлүүлэх', 'zh': '开始游戏'},
  'm13FriendHint': {
    'en': 'Private friend room · 2–4 players · host starts · points only',
    'mn': 'Найзын өрөө · 2–4 хүн · эзэн эхлүүлнэ · зөвхөн оноо',
    'zh': '好友私密房 · 2～4 人 · 房主开局 · 仅计积分',
  },
  'm13Dragon': {
    'en': '13 unique ranks — instant win',
    'mn': '13 өөр хөзөр — шууд ялалт',
    'zh': '十三张点数各异，直接获胜',
  },
  'error_m13_bad_combo': {
    'en': 'Invalid card combination',
    'mn': 'Хөзрийн хослол буруу',
    'zh': '所选手牌不是有效牌型',
  },
  'error_m13_opening': {
    'en': 'Include the opening card',
    'mn': 'Эхлэх хөзрийг оруулна уу',
    'zh': '首手需要包含指定的最小牌',
  },
  'error_m13_too_small': {
    'en': 'Play the same number of cards with a higher value',
    'mn': 'Ижил тооны илүү том хөзөр гаргана уу',
    'zh': '需要相同张数且更大的牌型',
  },
  'error_m13_cannot_pass': {
    'en': 'You must lead this turn',
    'mn': 'Энэ ээлжид хөзөр гаргах ёстой',
    'zh': '当前由你领出，不能过牌',
  },
  'error_m13_need_players': {
    'en': 'At least two players are required',
    'mn': 'Дор хаяж хоёр тоглогч хэрэгтэй',
    'zh': '至少两人坐下后才能开局',
  },
  'm13_single': {'en': 'Single', 'mn': 'Нэг', 'zh': '单张'},
  'm13_pair': {'en': 'Pair', 'mn': 'Хос', 'zh': '对子'},
  'm13_triple': {'en': 'Three of a kind', 'mn': 'Гурвал', 'zh': '三张'},
  'm13_four': {'en': 'Four of a kind', 'mn': 'Дөрөв', 'zh': '四张'},
  'm13_straight': {'en': 'Straight', 'mn': 'Дараалал', 'zh': '顺子'},
  'm13_flush': {'en': 'Flush', 'mn': 'Ижил масть', 'zh': '同花'},
  'm13_fullHouse': {'en': 'Full house', 'mn': 'Гурвал ба хос', 'zh': '三带二'},
  'm13_fourOne': {'en': 'Four plus one', 'mn': 'Дөрөв ба нэг', 'zh': '四带一'},
  'm13_straightFlush': {
    'en': 'Straight flush',
    'mn': 'Ижил мастийн дараалал',
    'zh': '同花顺',
  },
  'rtcRate': {
    'en': 'Table video: 10 coins/min · 1 coin per 6 seconds',
    'zh': '整桌视频：10 金币/分钟，每 6 秒扣 1 金币',
    'mn': 'Ширээний дүрс: 10 зоос/мин · 6 секундэд 1 зоос',
  },
  'rtcPayer': {'en': 'Paid by', 'zh': '付费人', 'mn': 'Төлөгч'},
  'rtcBalance': {'en': 'Your coins', 'zh': '你的金币', 'mn': 'Таны зоос'},
  'rtcCharging': {
    'en': 'Video billing active',
    'zh': '视频计费中',
    'mn': 'Дүрсний төлбөр тооцож байна',
  },
  'rtcPaused': {
    'en': 'Video billing paused',
    'zh': '视频计费已暂停',
    'mn': 'Дүрсний төлбөр түр зогссон',
  },
  'rtcPayTitle': {
    'en': 'Enable table video',
    'zh': '开通本桌视频',
    'mn': 'Ширээний дүрсийг нээх',
  },
  'rtcPayBody': {
    'en':
        'You pay 1 coin per 6 seconds for the whole table. Billing starts with video and at least two connected players, and pauses when all cameras are off. Leaving ends your sponsorship.',
    'zh': '由你为整桌付费，每 6 秒扣 1 金币。至少两人接入且有人开启视频时计费；全部关闭视频则暂停。你离桌后结束付费，不转扣其他玩家。',
    'mn':
        'Бүх ширээнд 6 секунд тутам 1 зоос төлнө. Хоёроос дээш хүн холбогдож дүрс асаасан үед тооцно. Камерууд унтарвал түр зогсоно. Та гарвал төлбөр дуусна.',
  },
  'rtcPayConfirm': {
    'en': 'Agree & enable camera',
    'zh': '同意并开启摄像头',
    'mn': 'Зөвшөөрч камер асаах',
  },
  'rtcSpeakerOn': {'en': 'Sound on', 'zh': '开启收听', 'mn': 'Дуу нээх'},
  'rtcSpeakerOff': {'en': 'Mute sound', 'zh': '关闭收听', 'mn': 'Дуу хаах'},
  'error_rtc_insufficient': {
    'en': 'Not enough coins. Video stopped; voice and game continue.',
    'zh': '金币不足，视频已停止，语音和打牌不受影响。',
    'mn': 'Зоос хүрэлцэхгүй. Дүрс зогссон; дуу, тоглолт үргэлжилнэ.',
  },
  'error_rtc_billing_failed': {
    'en': 'Video billing unavailable. Your game continues.',
    'zh': '视频扣费暂不可用，视频已停止，牌局继续。',
    'mn': 'Дүрсний төлбөр боломжгүй. Тоглолт үргэлжилнэ.',
  },
  'error_rtc_payment_required': {
    'en': 'Accept the table video price first.',
    'zh': '请先确认开通本桌视频及价格。',
    'mn': 'Эхлээд дүрсний үнийг зөвшөөрнө үү.',
  },
  'error_rtc_payer_left': {
    'en': 'The payer left. A new payer must enable video.',
    'zh': '付费人已离桌，重新开启视频需由新付费人确认。',
    'mn': 'Төлөгч гарсан. Шинэ төлөгч дүрсийг нээнэ үү.',
  },
  'error_rtc_payer_offline': {
    'en': 'The payer disconnected. Video is paused.',
    'zh': '付费人连接中断，视频已暂停。',
    'mn': 'Төлөгчийн холболт тасарсан. Дүрс түр зогссон.',
  },
  'error_rtc_closed': {
    'en': 'Table call ended.',
    'zh': '本桌通话已结束。',
    'mn': 'Ширээний яриа дууссан.',
  },
  'rtcTitle': {
    'en': "Table voice & video",
    'mn': "Ширээний дуу, дүрс",
    'zh': "同桌语音和视频",
  },
  'rtcPrivacy': {
    'en':
        "When someone starts voice or video, seated players automatically receive. Your microphone and camera stay off until you enable them.",
    'mn': "Сонсохоор нэгдэнэ. Микрофон, камерыг өөрөө асаана.",
    'zh': "有人开启音视频后，同桌自动接收。你的麦克风和摄像头由你主动开启。",
  },
  'rtcAndroidOnly': {
    'en': "Voice & video is available in the Android app.",
    'mn': "Дуу, дүрс Android апп дээр ажиллана.",
    'zh': "语音和视频请使用 Android 客户端。",
  },
  'rtcJoin': {'en': "Join audio", 'mn': "Дуут ярианд нэгдэх", 'zh': "加入语音"},
  'rtcLeave': {'en': "Leave call", 'mn': "Ярианаас гарах", 'zh': "退出通话"},
  'rtcMicOn': {'en': "Unmute", 'mn': "Микрофон асаах", 'zh': "开启麦克风"},
  'rtcMicOff': {'en': "Mute", 'mn': "Микрофон унтраах", 'zh': "关闭麦克风"},
  'rtcCameraOn': {'en': "Camera on", 'mn': "Камер асаах", 'zh': "开启摄像头"},
  'rtcCameraOff': {'en': "Camera off", 'mn': "Камер унтраах", 'zh': "关闭摄像头"},
  'rtcSwitchCamera': {
    'en': "Switch camera",
    'mn': "Камер солих",
    'zh': "切换摄像头",
  },
  'rtcMutePeer': {
    'en': "Mute this player",
    'mn': "Тоглогчийн дууг хаах",
    'zh': "屏蔽该玩家声音",
  },
  'rtcUnmutePeer': {
    'en': "Unmute this player",
    'mn': "Тоглогчийн дууг нээх",
    'zh': "恢复该玩家声音",
  },
  'rtcWeak': {
    'en': "Weak network · video may pause to preserve audio",
    'mn': "Сүлжээ сул · дууг хадгалахын тулд дүрс түр зогсож болно",
    'zh': "网络较弱，视频可能暂停以优先保障语音",
  },
  'rtcReconnecting': {
    'en': "Reconnecting call…",
    'mn': "Яриаг дахин холбож байна…",
    'zh': "通话重连中…",
  },
  'error_rtc_unavailable': {
    'en': "Table calls are not available yet. You can keep playing.",
    'mn': "Ширээний яриа одоогоор боломжгүй. Тоглолтоо үргэлжлүүлээрэй.",
    'zh': "同桌通话暂未开通，可继续打牌。",
  },
  'error_rtc_not_seated': {
    'en': "Take a seat to join this table’s call.",
    'mn': "Ширээнд сууж байж ярианд нэгдэнэ.",
    'zh': "入座后才能加入本桌通话。",
  },
  'error_rtc_retry': {
    'en': "Please wait a moment and try again.",
    'mn': "Түр хүлээгээд дахин оролдоно уу.",
    'zh': "请稍后重试。",
  },
  'error_rtc_failed': {
    'en': "Call interrupted. Rejoin when ready; your game continues.",
    'mn': "Яриа тасарлаа. Дахин нэгдэж болно; тоглолт үргэлжилнэ.",
    'zh': "通话中断，可重新加入；牌局不受影响。",
  },
  'error_rtc_mic_permission': {
    'en':
        "Microphone permission is off. Allow it in app settings to speak. You can still listen.",
    'mn':
        "Микрофоны зөвшөөрөл хаалттай. Аппын тохиргооноос зөвшөөрнө үү. Сонсох боломжтой.",
    'zh': "未获得麦克风权限，可在系统设置中允许；仍可收听。",
  },
  'error_rtc_camera_permission': {
    'en': "Camera permission is off. Allow it in app settings to use video.",
    'mn': "Камерын зөвшөөрөл хаалттай. Аппын тохиргооноос зөвшөөрнө үү.",
    'zh': "未获得摄像头权限，可在系统设置中允许；语音不受影响。",
  },
  'lobby': {'en': 'Lobby', 'mn': 'Танхим', 'zh': '大厅'},
  'profile': {'en': 'My profile', 'mn': 'Миний мэдээлэл', 'zh': '我的'},
  'connected': {
    'en': 'Connected · ready to play',
    'mn': 'Холбогдсон · тоглоход бэлэн',
    'zh': '已连接 · 随时入座',
  },
  'lobbyTitle': {'en': 'Take a seat.', 'mn': 'Ширээнд суу.', 'zh': '找一桌，开一局'},
  'lobbySubtitle': {
    'en': 'Good company. A great hand.',
    'mn': 'Сайн нөхөд. Сайхан тоглолт.',
    'zh': '与牌友相聚，从一手好牌开始',
  },
  'joinByCode': {'en': 'Enter code', 'mn': 'Код оруулах', 'zh': '输入房号'},
  'allTables': {'en': 'All tables', 'mn': 'Бүх ширээ', 'zh': '全部'},
  'availableTables': {'en': 'Open seats', 'mn': 'Сул суудал', 'zh': '可入座'},
  'waitingStatus': {'en': 'Waiting', 'mn': 'Хүлээж байна', 'zh': '待开局'},
  'playingStatus': {'en': 'Playing', 'mn': 'Тоглож байна', 'zh': '进行中'},
  'practiceTable': {
    'en': 'Bot practice',
    'mn': 'Боттой бэлтгэл',
    'zh': '机器人练习桌',
  },
  'publicTable': {'en': 'Public table', 'mn': 'Нээлттэй ширээ', 'zh': '公开牌桌'},
  'humans': {'en': 'human', 'mn': 'хүн', 'zh': '真人'},
  'bots': {'en': 'bots', 'mn': 'бот', 'zh': '机器人'},
  'seated': {'en': 'seated', 'mn': 'суусан', 'zh': '已入座'},
  'readyToJoin': {
    'en': 'Join before the first hand',
    'mn': 'Эхлэхээс өмнө ороорой',
    'zh': '入座后即可开始',
  },
  'takeSeat': {'en': 'Take a seat', 'mn': 'Суух', 'zh': '入座'},
  'fullTable': {'en': 'Full', 'mn': 'Дүүрсэн', 'zh': '已满'},
  'loadingRooms': {
    'en': 'Finding tables…',
    'mn': 'Ширээ хайж байна…',
    'zh': '正在加载牌桌…',
  },
  'refresh': {'en': 'Refresh tables', 'mn': 'Шинэчлэх', 'zh': '刷新列表'},
  'retry': {'en': 'Retry', 'mn': 'Дахин оролдох', 'zh': '重试'},
  'dismiss': {'en': 'Dismiss', 'mn': 'Хаах', 'zh': '知道了'},
  'close': {'en': 'Close', 'mn': 'Хаах', 'zh': '关闭'},
  'quickChat': {'en': 'Quick phrases', 'mn': 'Бэлэн үгс', 'zh': '快捷用语'},
  'connectionFailed': {
    'en': 'Could not connect. Please try again.',
    'mn': 'Холбогдож чадсангүй. Дахин оролдоно уу.',
    'zh': '暂时无法连接，请重试。',
  },
  'connectionHint': {
    'en': 'You can practise offline while we connect.',
    'mn': 'Холбогдох зуур офлайнаар бэлтгэл хийж болно.',
    'zh': '连接期间，可以先玩一局单机练习。',
  },
  'roomsFailed': {
    'en': 'Could not refresh tables. Please retry.',
    'mn': 'Ширээг шинэчилж чадсангүй. Дахин оролдоно уу.',
    'zh': '房间列表刷新失败，请重试。',
  },
  'noMatchingRooms': {
    'en': 'No tables match this filter yet.',
    'mn': 'Тохирох ширээ одоогоор алга.',
    'zh': '暂无符合条件的房间',
  },
  'showAllRooms': {
    'en': 'Show all tables',
    'mn': 'Бүх ширээг харах',
    'zh': '查看全部房间',
  },
  'error_login_failed': {
    'en': 'Could not sign in. Please reconnect.',
    'mn': 'Нэвтэрч чадсангүй. Дахин холбогдоно уу.',
    'zh': '登录未成功，请重新连接。',
  },
  'tableLabel': {'en': 'Table', 'mn': 'Ширээ', 'zh': '牌桌'},
  'chat': {'en': 'Chat', 'mn': 'Чат', 'zh': '聊天'},
  'cardReturned': {
    'en': 'Card returned to your hand.',
    'mn': 'Хөзөр гарт буцлаа.',
    'zh': '牌已退回手中。',
  },
  'error_illegal_card': {
    'en': 'Follow the required suit or trump.',
    'mn': 'Шаардлагатай масть эсвэл козыроор тоглоно уу.',
    'zh': '请按跟牌、主牌规则出牌。',
  },
  'error_not_your_turn': {
    'en': 'It is no longer your turn.',
    'mn': 'Таны ээлж биш байна.',
    'zh': '当前已不是你的回合。',
  },
  'error_wrong_phase': {
    'en': 'The table has moved to the next phase.',
    'mn': 'Тоглолт дараагийн үе шатанд шилжлээ.',
    'zh': '牌局已进入下一阶段。',
  },
  'error_card_not_in_hand': {
    'en': 'This card is no longer in your hand.',
    'mn': 'Энэ хөзөр таны гарт байхгүй байна.',
    'zh': '这张牌已不在你的手牌中。',
  },
  'error_timeout': {
    'en': 'The request timed out. Please try again.',
    'mn': 'Хүсэлтийн хугацаа дууссан. Дахин оролдоно уу.',
    'zh': '请求超时，请重试。',
  },
  'error_disconnected': {
    'en': 'Connection lost. Reconnecting…',
    'mn': 'Холболт тасарлаа. Дахин холбогдож байна…',
    'zh': '连接已断开，正在重连…',
  },
  'error_already_in_room': {
    'en': 'Return to your current game first.',
    'mn': 'Одоогийн тоглолт руугаа буцна уу.',
    'zh': '你已在牌局中，请先返回当前牌局。',
  },
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
  'openSeat': {'en': 'Open seat', 'mn': 'Сул суудал', 'zh': '空位'},
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
  'trumpTakenHint': {
    'en': 'The dealer took the face-up card. The trump suit stays the same.',
    'mn': 'Тараагч дэлгэсэн хөзрийг авсан. Козырийн масть өөрчлөгдөхгүй.',
    'zh': '庄家已换走亮牌，主花色不变。',
  },
  'stock': {'en': 'Stock', 'mn': 'Нөөц', 'zh': '牌堆'},
  'playBtn': {'en': 'Play', 'mn': 'Тоглоно', 'zh': '打'},
  'passBtn': {'en': 'Pass', 'mn': 'Өнжинө', 'zh': '弃'},
  'waitingDecisions': {
    'en': 'Waiting for other players to decide…',
    'mn': 'Бусад тоглогчдын шийдвэрийг хүлээж байна…',
    'zh': '等待其他玩家选择…',
  },
  'keepAll': {'en': 'Keep all', 'mn': 'Солихгүй', 'zh': '不换牌'},
  'takeTrumpBtn': {'en': 'Navsh ⇄', 'mn': 'Навш ⇄', 'zh': 'Navsh 换'},
  'takeHint': {
    'en': 'Navsh: pick one card to trade for the face-up trump',
    'mn': 'Навш: ил хөзрөөр солих нэг хөзрөө сонго',
    'zh': 'Navsh：选一张牌换走明牌',
  },
  'navshSkip': {'en': 'Keep hand', 'mn': 'Солихгүй', 'zh': '不换'},
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
  'points': {'en': 'Points', 'mn': 'Оноо', 'zh': '积分'},
  'leaveTitle': {
    'en': 'Leave the game?',
    'mn': 'Тоглолтоос гарах уу?',
    'zh': '离开牌局？',
  },
  'dissolveRoomTitle': {
    'en': 'Dissolve this room?',
    'mn': 'Өрөөг тараах уу?',
    'zh': '解散房间？',
  },
  'dissolveRoomBody': {
    'en':
        'The game has not started. Leaving as host will dissolve the room for everyone.',
    'mn': 'Тоглолт эхлээгүй байна. Эзэн гарвал өрөө бүх хүнд хаагдана.',
    'zh': '牌局尚未开始，房主退出将解散房间，所有玩家返回大厅。',
  },
  'dissolveRoom': {'en': 'Dissolve room', 'mn': 'Өрөө тараах', 'zh': '解散房间'},
  'roomDissolved': {
    'en': 'The host dissolved the room.',
    'mn': 'Эзэн өрөөг тараалаа.',
    'zh': '房主已解散房间。',
  },
  'leaveRoomTitle': {
    'en': 'Leave this room?',
    'mn': 'Өрөөнөөс гарах уу?',
    'zh': '退出房间？',
  },
  'leaveRoomBody': {
    'en': 'The game has not started. You can leave without a penalty.',
    'mn': 'Тоглолт эхлээгүй тул торгуульгүй гарч болно.',
    'zh': '牌局尚未开始，退出不计失败，房间继续保留。',
  },
  'leaveBody': {
    'en':
        'Your seat will be handed to the system and this counts as a loss. You cannot return to this game.',
    'mn':
        'Суудлыг тань систем авч, энэ нь хожигдолд тооцогдоно. Энэ тоглолт руу буцах боломжгүй.',
    'zh': '离开后本局将交由系统托管代打并记为一败，无法返回本局。',
  },
  'leaveBtn': {'en': 'Leave', 'mn': 'Гарах', 'zh': '离开'},
  'watch': {'en': 'Watch', 'mn': 'Үзэх', 'zh': '观战'},
  'rooms': {'en': 'Rooms', 'mn': 'Өрөөнүүд', 'zh': '房间列表'},
  'sit': {'en': 'Sit down', 'mn': 'Суух', 'zh': '坐下'},
  'noSeatAvailable': {
    'en': 'No free seat',
    'mn': 'Сул суудал алга',
    'zh': '暂无空位',
  },
  'error_already_started': {
    'en': 'This table no longer accepts seats. You can keep watching.',
    'mn': 'Суудал авах боломжгүй. Үргэлжлүүлэн үзэж болно.',
    'zh': '当前牌桌暂不可入座，可以继续观战。',
  },
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
