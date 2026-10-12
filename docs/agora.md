# 同桌语音和视频（Android）

牌桌右上角耳机按钮 →「加入语音」。默认只收听；点击开启麦克风/摄像头时才申请对应权限。五人桌为上方三席、下方两席，自己固定在右下方；圆角竖向视频窗口关闭时显示默认头像，名字和头顶赢牌保留。回合 CD 沿窗口边缘递减，手牌和横排操作栏置于底部。支持单独屏蔽其他玩家声音、切换前后摄像头、说话指示。

摄像头为 320×240 / 15 fps / 200 kbps，远端默认订阅小流，弱网订阅可降级到纯语音。通话中暂停背景音乐、降低牌局音效，退出后按用户原设置恢复。网络表现须在蒙古国真实 Wi-Fi/移动网络实测，代码测试不能代替。

当前仅 Android 开放入口能力；网页仍可打牌，会提示使用 Android 客户端。未接入录制、后台通话或直播观众。旁观者和机器人不获取 Token。退出牌桌、牌局结束、游戏连接断开、账号被顶下线或切到后台均退出通话；回到前台需主动重新加入。

## 创建项目与服务端配置

1. 在 [Agora Console](https://console.agora.io/) 创建国际版 RTC 项目，启用 **App Certificate / Token 鉴权**。使用应用 ID 无 Token 的测试模式不适用。
2. 在运行 Skynet 的 Linux/WSL 服务端复制 `server/.env.rtc.example` 到 `server/.env.rtc`，填写 `AGORA_APP_ID`、`AGORA_APP_CERTIFICATE`。该文件已被 Git 忽略。不要填写到 Flutter、提交到仓库或发送到聊天。Linux 上设置 `chmod 600 .env.rtc`。
3. 需要 Python 3.9+（推荐 3.12），没有 pip 依赖。通过 `server/run.sh` 启动服务器；Windows 使用 `scripts/start-local-server.ps1`。直接运行 Skynet 二进制不会启动 Token 服务。
4. 配置后重启游戏服务器。启动脚本自动启动仅监听 `127.0.0.1:9760` 的签名进程，并为本次运行生成内部随机密钥；退出时清理子进程。不要映射/公开 9760 端口。没配置凭证时正常启动打牌服务，通话返回 `rtc_unavailable`。
5. 用新 APK 连接更新后的服务器。同桌两台 Android 真机各自加入语音，再分别开启麦克风和摄像头。线上使用 WSS，避免登录和短期 RTC Token 经过明文 WebSocket；当前项目默认服务器 URL 未改动。

无需数据库新表、Agora App ID 编译参数或 APK 内置证书。只更新 APK 而未更新后端无法使用通话。

## 鉴权与协议

客户端请求 `{cmd: "rtc_token", code: "六位房号"}`；同一命令用于续期。后端从已登录 socket 找到当前房间，核对真人座位、在线状态、agent/fd、房号及游戏未结束，生成当前房间随机频道和玩家 UID 的 AccessToken2。客户端不能指定频道、UID、角色、有效期。签名 HTTP 返回后再次检查座位与 socket，防止等待期间离桌。

响应包含 `app_id / channel / uid / token / expires_at / renew_after`。有效期及所有媒体权限为 300 秒，客户端 240 秒续期，并处理 SDK 提前过期回调。续期失败退出媒体，不影响牌局。频道是每个房间实例独立的 128 位随机值，复用六位房号不会复用媒体频道。玩家的 `rtc_uid` 随座位列表公开，用于对应视频和头像，机器人没有该字段。

限制：SDK 主动退出负责正常客户端即时离开。已签发 Token 无法通过本地离桌直接吊销，修改版客户端可能继续使用旧 Token 最长 300 秒；离桌后不能续签。此版本没有调用 Agora 云端封禁 REST API。若需要对恶意客户端即时强制踢出，须另配置 Agora REST 凭证并接入云端封禁，不能声称当前 Token 方案提供即时撤销。

官方签名 SDK 固定版本及许可证见 `server/rtc/vendor/README.md`。使用 [Agora 推荐的 AccessToken2](https://github.com/AgoraIO/Tools/tree/da06bfb83556c597bfcb7db65fa65c975165a130/DynamicKey/AgoraDynamicKey)。

## 验证

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
