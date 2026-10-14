# 同桌语音和视频（Android）

牌桌右上角耳机按钮打开音视频面板。首次有人开启麦克风或摄像头后，服务端启用本桌通话，其他已坐下的 Android 真人玩家自动加入接收，自己的设备保持关闭。界面不再提供单独的加入或退出通话按钮；可分别控制麦克风、摄像头、收听和切换镜头。权限仅在本人开启对应设备时申请。

五人桌为上方三席、下方两席，自己固定在右下方；圆角视频窗口关闭时显示默认头像，名字和头顶赢牌保留。回合 CD 沿窗口边缘递减，手牌和横排操作栏置于底部。

摄像头为 320×240 / 15 fps / 200 kbps，远端默认订阅小流，弱网订阅可降级到纯语音。通话中暂停背景音乐、降低牌局音效，退出后按用户原设置恢复。网络表现须在蒙古国真实 Wi-Fi/移动网络实测，代码测试不能代替。

当前仅 Android 开放入口能力；网页仍可打牌，会提示使用 Android 客户端。未接入录制、后台通话或直播观众。旁观者和机器人不获取 Token。退出牌桌、牌局结束、游戏连接断开、账号被顶下线或切到后台均释放通话资源；回来时若本桌已启用通话则自动恢复接收，不自动重新开启自己的设备。全部关麦关视频时保留本桌通话的启用状态。

## 视频金币计费

整桌视频每累计 6 秒扣固定付费人 1 金币，即每分钟 10 金币。首次开通前显示价格和付费确认，不能由客户端指定扣其他人的钱包。同桌其他玩家免费接收和参与，多个摄像头不叠加扣款；纯语音当前不扣金币。

- 使用现有金币余额，包含注册和任务赠送金币；未区分充值金币，也未接入新的充值支付渠道。
- 至少两名真人客户端已连接本桌 RTC，且至少一个摄像头发布成功后开始计时。客户端等 Agora 发布成功回调后再报告视频状态。
- 全部关闭视频或接入人数不足时暂停，同一付费人的不足 6 秒余量保留到恢复后累计。离桌或房间结束时不足 6 秒部分不补扣。
- 付费人离桌会关闭全桌视频并清除付费人。新付费人必须重新确认，绝不自动转扣其他玩家。
- 余额不足或扣费失败时关闭视频，保留语音与牌局；余额增加后需主动再次开启摄像头。
- 客户端每 5 秒报告媒体状态；15 秒未报告视为失联，停止对应计时。正常离桌、后台和断线流程主动清理状态。
- 服务端使用自身时钟和单一计费循环；`rtc_charge` 表以唯一扣费键记录流水，MySQL 事务保证钱包扣减和流水一起提交。钱包事务失败时停止视频，不使用内存钱包继续收费。

新增协议 `rtc_control`：`start` 启用本桌通话，`prepare` 确认视频付费人，`state` 报告媒体状态和心跳。房间快照与 `rtc_state` 推送携带启用状态、付费人、计费状态和视频失效版本；`rtc_balance` 仅通知被扣费玩家自己的余额。房间、座位和当前 socket 都由服务端校验。

该版本针对官方客户端完成计费闭环。实际发布状态目前由客户端 SDK 回调上报，未接 Agora 服务端媒体事件核验；已发 Token 的发布权限不会随余额不足立即撤销，改版客户端可能绕过停止视频指令。对外销售充值金币前，应补媒体事件核验和 Agora 服务端发布权限或封禁控制，不能把本版描述成防篡改付费墙。

服务端修改直接保存在 `sichuan:/opt/khuzur/server`。接入 Durak 好友局时，已将当前房间、代理、数据库计费及 RTC 模块同步至本机 server 源码，服务器配置仍由各环境单独管理。计费上线前备份位于 `/opt/khuzur-backups/rtc-billing-20261013-163404`。当前通过 `khuzur.service` 管理，日志使用 `journalctl -u khuzur -f`。

## 创建项目与服务端配置

1. 在 [Agora Console](https://console.agora.io/) 创建国际版 RTC 项目，启用 **App Certificate / Token 鉴权**。使用应用 ID 无 Token 的测试模式不适用。
2. 在运行 Skynet 的 Linux/WSL 服务端复制 `server/.env.rtc.example` 到 `server/.env.rtc`，填写 `AGORA_APP_ID`、`AGORA_APP_CERTIFICATE`。该文件已被 Git 忽略。不要填写到 Flutter、提交到仓库或发送到聊天。Linux 上设置 `chmod 600 .env.rtc`。
3. 需要 Python 3.9+（推荐 3.12），没有 pip 依赖。通过 `server/run.sh` 启动服务器；Windows 使用 `scripts/start-local-server.ps1`。直接运行 Skynet 二进制不会启动 Token 服务。
4. 配置后重启游戏服务器。启动脚本自动启动仅监听 `127.0.0.1:9760` 的签名进程，并为本次运行生成内部随机密钥；退出时清理子进程。不要映射/公开 9760 端口。没配置凭证时正常启动打牌服务，通话返回 `rtc_unavailable`。
5. 用新 APK 连接 `wss://kzur.sdg8888.com/ws`。同桌两台 Android 真机中一台开启麦克风，确认另一台自动接收；再确认价格并开启视频，检查画面和扣币。构建时指定新 WSS 地址；用户已保存的旧地址仍需在设置中修改。

计费版会在数据库启动时自动创建 `rtc_charge` 扣费流水表，需要业务用户具备建表权限。无需 Agora App ID 编译参数或 APK 内置证书。只更新 APK 而未更新后端无法使用新逻辑。

## 鉴权与协议

客户端请求 `{cmd: "rtc_token", code: "六位房号"}`；同一命令用于续期。后端从已登录 socket 找到当前房间，核对真人座位、在线状态、agent/fd、房号及游戏未结束，生成当前房间随机频道和玩家 UID 的 AccessToken2。客户端不能指定频道、UID、角色、有效期。签名 HTTP 返回后再次检查座位与 socket，防止等待期间离桌。

响应包含 `app_id / channel / uid / token / expires_at / renew_after`。有效期及所有媒体权限为 300 秒，客户端 240 秒续期，并处理 SDK 提前过期回调。续期失败退出媒体，不影响牌局。频道是每个房间实例独立的 128 位随机值，复用六位房号不会复用媒体频道。玩家的 `rtc_uid` 随座位列表公开，用于对应视频和头像，机器人没有该字段。

限制：SDK 主动退出负责正常客户端即时离开。已签发 Token 无法通过本地离桌直接吊销，修改版客户端可能继续使用旧 Token 最长 300 秒；离桌后不能续签。此版本没有调用 Agora 云端封禁 REST API。若需要对恶意客户端即时强制踢出，须另配置 Agora REST 凭证并接入云端封禁，不能声称当前 Token 方案提供即时撤销。

官方签名 SDK 固定版本及许可证见 `server/rtc/vendor/README.md`。使用 [Agora 推荐的 AccessToken2](https://github.com/AgoraIO/Tools/tree/da06bfb83556c597bfcb7db65fa65c975165a130/DynamicKey/AgoraDynamicKey)。

## 验证

计费服务端用例保存在四川服务器，执行以下命令可验证纯逻辑；`test_rtc_wallet` 会在当前配置的 MySQL 中创建诊断账户并测试流水，`rtc_billing_e2e.py` 会创建两名诊断玩家、一个私密房间并消耗少量诊断账户金币，不发布真实音视频：

```sh
cd /opt/khuzur/server
./skynet/3rd/lua/lua test/test_rtc_billing.lua
./skynet/3rd/lua/lua test/test_rtc_grant.lua
./skynet/skynet etc/config.rtc_wallet
python3 test/rtc_billing_e2e.py
```

```sh
cd app
flutter analyze
flutter test
flutter build apk --debug
# Linux / WSL，仓库根目录
cd server
python3 -m unittest discover -s rtc -p 'test_*.py' -v
./skynet/3rd/lua/lua test/test_rtc_grant.lua
python3 rtc/check_skynet.py
```

交付前真机验收：两至五人同桌、不同房间隔离、摄像头/麦克风拒绝及永久拒绝、至少十分钟续期、单人离桌/重登、后台/锁屏、网络断开重连、耳机/外放。确认权限未主动打开时没有采集指示，视频关闭释放摄像头、退出关闭所有采集。无 Agora 项目凭证时只验证代码、签名和构建，不能验证云端通话质量或实际计费。

### Windows 构建备注

Agora/Iris 插件读取根项目的 `compileSdkVersion`，已在 `app/android/build.gradle.kts` 设为 36，解决其默认 API 31 与 Flutter AndroidX 依赖不兼容的问题。

本机 Kotlin 增量编译缓存报错时，可在 `app/android` 使用临时命令绕开缓存，不改全局 Gradle 设置：

```powershell
# JAVA_HOME 指向本机 Android Studio 的 jbr；先正常运行 flutter pub get。
.\gradlew.bat --no-daemon '-Pkotlin.incremental=false' '-Pkotlin.compiler.execution.strategy=in-process' assembleDebug
```

调试 APK 输出为 `app/build/app/outputs/flutter-apk/app-debug.apk`。这是调试包；正式上架仍需配置应用 ID、发布签名及隐私说明。
