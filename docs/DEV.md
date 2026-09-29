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
