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
