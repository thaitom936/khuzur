# khuzur 开发说明

蒙古纸牌游戏 Muushig。客户端 Flutter（`app/`，竖屏），服务端 Skynet（`server/`）。

## 目录

```
app/                    Flutter 客户端
  lib/rules/            Dart 规则引擎（纯 Dart，无 Flutter 依赖）
  lib/bot/              单机 AI
  lib/game/             GameController 接口 + 本地/远程实现
  lib/net/              WebSocket 客户端、会话（游客登录/token/重连）
  lib/online/           在线大厅、排行榜
  lib/play_session/     牌桌 UI（单机和联机共用）
  lib/l10n/             en/mn/zh 文本（mn 为机翻，需母语者校对）
server/
  skynet/               git submodule（已编译）
  lualib/rules/         Lua 规则引擎 + AI（与 Dart 版行为一致）
  lualib/json.lua       协议 JSON 编解码
  service/              main wsgate ws_agent hub match room db
  etc/config            正式配置（端口 9601，redis db1）
  etc/config.test       e2e 测试配置（端口 9611，redis db2，快速计时）
  test/                 规则用例运行器 + e2e 测试
testdata/rules/         共享规则用例（Dart/Lua 各跑一遍保持一致）
```

## 常用命令

```sh
# 规则用例（Lua，本机可跑）
lua5.4 server/test/run_rules.lua            # 仓库根目录执行

# 服务端 e2e（登录/匹配/好友房/整场牌局）
cd server && redis-cli -n 2 flushdb && ./skynet/skynet etc/config.test

# 启动开发服（前台）
cd server && ./run.sh

# 客户端（在装有 Flutter 的机器上）
cd app && flutter test && flutter run
```

## 协议

WebSocket 文本帧，JSON。请求 `{seq, cmd, ...}`，响应 `{seq, cmd, err?, ...}`，
推送 `{push: "...", ...}`。命令与推送清单见 `server/service/ws_agent.lua`
和 `server/service/room.lua` 顶部注释。牌的字符串形如 `7C`/`TD`/`AH`。

## 环境依赖

- 服务器：lua5.4（跑规则用例）、redis（必须）、MySQL（可选，
  连不上时 db 服务自动降级为内存模式，重启丢数据）
- MySQL 8.4 注意：skynet 的 mysql 驱动只支持 mysql_native_password，
  需要在 mysqld 配置里开启 `mysql_native_password=ON` 并用该插件建账号
- 客户端联机默认地址在 `app/lib/net/session.dart`（可在设置页改）；
  AWS 安全组需放行 TCP 9601
- Android 清单已开 `usesCleartextTraffic`（开发用 ws://）；
  上线前需换成 nginx + wss 并移除该开关

## 金币与好友（2026-09-29 增补）

- 新用户 1000 金币；每日签到 +200；任务：3 场 +100、赢 1 场 +150、10 墩 +100
  （db.lua 的 TASKS 表，按乌兰巴托 UTC+8 日期重置，进度存 redis）
- 场次门票：0/100/500/2000。agent 在排队/进房时托管扣款，取消或离房退款；
  奖池 = 门票 × 真人数量，赢家平分，机器人赢的份额销毁；
  金币场至少 2 个真人才会补机器人开局
- 好友：申请/接受模型（friend 表双向行）；invite 命令把房间号推给在线好友
- 新增客户端页面：好友（/online/friends）、每日奖励弹层、门票选择弹层

## 观战与回放（2026-09-29 增补）

- 观战：好友列表中在局的好友显示"观战"；watch/unwatch 命令；
  观战者收到全部广播但永远拿不到手牌（snapshot you=-1）
- 回放：room 全程录像（每局发牌 + 每步动作），game_end 存 redis 30 天，
  每人保留最近 10 场；客户端用本地 Dart 规则引擎逐步重放（replay_controller.dart），
  录像格式的正确性由 e2e 用 Lua 引擎整场重放校验

## 大厅房间列表（2026-09-29 增补）

- 所有房间（快速场+好友房）统一分配 6 位房号并公开列出（room_list 命令）
- "坐下"：未开局补空位；已开局的免费场可顶替机器人入座（金币场不行，
  奖池已定）；顶替后全桌广播新快照，若正轮到该座位则计时器重开
- "观战"支持按房号（watch {code}），与按好友 uid 并存
- 注意：好友房目前也是公开可见的；上锁房间留给 Pro 订阅做

## 房间玩法调整（2026-09-29 第二批）

- 金币场暂停：`stakes_enabled = "false"`（服务端拒绝带门票请求，
  客户端撤掉了门票选择和快速匹配入口）；金币/签到/任务系统保留
- 好友房可选"私密"（locked）：不在大厅列表显示，仅凭房号或邀请进入
- 常驻机器人房：`bot_rooms = 5`，服务器保持 5 个全机器人 5 人桌全天候
  开打，大厅可观战或坐下顶替；一场结束由 hub 自动补新房
- 验证：`./skynet/skynet etc/config.botrooms`（保活/坐下/观战/禁门票）

## 局的边界与等级积分（2026-09-30）

- 一局 = 15 分打到 0；开局后不可再坐下（join 一律 already_started）
- 中途离开 = 弃局：确认弹窗后座位永久转机器人（保留昵称）、立即解绑
  可加入新游戏、记一场败局并按等级扣积分；门票不退（金币场开启时）
- 断线≠弃局：仍是临时托管+重连回桌
- 等级积分：user_stat.rating，5 档（0/100/300/700/1500 起），胜 +20/16/12/10/8，
  负 -0/2/4/6/8（见 db.lua LEVELS）；排行榜改按积分（redis rank:rating）
- 客户端：好友入口暂时隐藏（代码保留）；资料与排行显示 Lv/积分
