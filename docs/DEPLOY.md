# Khuzur 新服务器部署

适用于 Ubuntu 24.04，项目安装在 `/opt/khuzur`。MySQL、Redis、Skynet 和 Agora Token 服务直接运行在服务器上，由 systemd 管理，无需 Docker。域名和 Web 页面在后端验证通过后配置。

以下服务器命令在 Linux SSH 终端执行。`新服务器IP`、`登录用户`、`game.example.com` 都需要替换成实际值。这是部署操作说明，不代表新服务器已经部署完成。

## 当前 WSS 部署

2026 年 10 月 13 日已在 SSH 别名 `sichuan` 的服务器 `47.109.30.174` 上配置：

- 游戏连接地址：`wss://kzur.sdg8888.com/ws`，公网端口为 443。
- Nginx 转发目标：`http://127.0.0.1:9601`。
- 线上配置：`/etc/nginx/conf.d/khuzur.conf`；仓库副本：[Nginx 配置](../server/deploy/nginx-khuzur.conf)。
- 证书目录：`/etc/letsencrypt/live/kzur.sdg8888.com/`。服务器已有 Certbot 定时任务，证书使用 Nginx 插件续期和安装。
- 访问日志：`/var/log/nginx/khuzur.access.log`；错误日志：`/var/log/nginx/khuzur.error.log`。

已验证公网 TLS 证书、WebSocket 101 握手、WSS 游客登录和大厅返回 5 个房间。HTTPS 根地址目前为连接说明页，尚未在该域名发布游戏 Web 页面。

现有 APK 需在设置中保存上述 WSS 地址，再重新打开游戏。此配置不改 APK 的默认地址，也不会覆盖客户端已保存的地址。2026 年 10 月 13 日已将游戏后端切换到 `khuzur.service` 后台托管，可安全关闭 SSH；使用 `sudo journalctl -u khuzur -f` 查看日志。自动接入、视频扣币和好友玩法代码直接在 sichuan 更新，接入 Durak 后已同步当前服务端运行模块至本机 server 目录；发布时保留目标服务器的配置和凭证。

## 1 准备环境

```bash
sudo apt update
sudo apt install -y git build-essential autoconf automake libtool python3 curl nginx mysql-server redis-server
```

使用 Ubuntu 24.04 自带的 MySQL 8.0 软件包，不额外添加其他 MySQL 大版本的软件源。启动数据库并检查版本：

```bash
sudo systemctl enable --now mysql redis-server
mysql --version
redis-server --version
```

本项目当前 MySQL 驱动使用旧式密码认证，业务账户需要 `mysql_native_password`。如果实际安装的不是 MySQL 8.0，先确认认证插件兼容性，不直接照搬建用户步骤。参考 [Ubuntu MySQL 安装说明](https://ubuntu.com/server/docs/databases-mysql/)和 [MySQL 认证插件说明](https://dev.mysql.com/doc/refman/8.0/en/pluggable-authentication.html)。

## 2 拉取代码并编译

本机先提交并推送需要部署的代码，包括 Agora 后端改动。`server/.env` 已被 Git 忽略，必须在服务器单独配置。

服务器需要有 GitHub 仓库读取权限。以下使用 SSH 克隆：

```bash
sudo mkdir -p /opt/khuzur
sudo chown "$USER":"$(id -gn)" /opt/khuzur
git clone --recurse-submodules git@github.com:thaitom936/khuzur.git /opt/khuzur
cd /opt/khuzur
git submodule update --init --recursive
make -C server/skynet linux -j2
```

在目标服务器编译 Skynet，不直接复用本机或其他架构的二进制。

## 3 配置数据库

### MySQL 建库和账户

Ubuntu 新安装的 MySQL 可以通过本机管理员身份进入，不必改变 root 账户认证方式：

```bash
sudo env MYSQL_HISTFILE=/dev/null mysql
```

在 MySQL 提示符中执行，先将 `替换为服务器专用强密码` 换成实际密码：

```sql
CREATE DATABASE IF NOT EXISTS khuzur CHARACTER SET utf8mb4;
CREATE USER 'khuzur'@'127.0.0.1'
  IDENTIFIED WITH mysql_native_password BY '替换为服务器专用强密码';
GRANT ALL PRIVILEGES ON khuzur.* TO 'khuzur'@'127.0.0.1';
EXIT;
```

业务账户只授予 `khuzur` 数据库权限，其中建表和改表权限用于后端启动时初始化和升级结构。该步骤针对新服务器；如果账户已存在，先检查已有配置，不删除或重建现有账户。

编辑 `/etc/mysql/mysql.conf.d/mysqld.cnf`，确认 `[mysqld]` 段的已有配置为：

```ini
bind-address = 127.0.0.1
mysqlx-bind-address = 127.0.0.1
```

### Redis 回环监听和持久化

编辑 `/etc/redis/redis.conf`，修改已有配置行：

```text
bind 127.0.0.1 -::1
protected-mode yes
appendonly yes
appendfsync everysec
```

本流程使用专用于游戏的本机 Redis。当前游戏连接代码没有配置 Redis 密码，因此采用回环监听并禁止公网访问；不要直接给它开启需要密码的认证而不修改游戏连接代码。保留默认数据库数量，游戏使用 DB 1。

### 对齐游戏配置并验证

编辑 `/opt/khuzur/server/etc/config` 中的对应字段：

```lua
mysql_host = "127.0.0.1"
mysql_port = 3306
mysql_db = "khuzur"
mysql_user = "khuzur"
mysql_password = "与上述业务账户一致的密码"

redis_host = "127.0.0.1"
redis_port = 6379
redis_db = 1
```

含服务器密码的本地配置修改不要提交到 Git。更新代码前检查配置冲突，不用 `git reset --hard` 覆盖它们。

```bash
sudo systemctl restart mysql redis-server
sudo systemctl is-active mysql redis-server
mysql --protocol=TCP -h 127.0.0.1 -u khuzur -p khuzur -e 'SELECT 1;'
redis-cli -h 127.0.0.1 -n 1 ping
sudo ss -lntp | grep -E ':(3306|33060|6379)\b'
```

MySQL 命令会提示输入密码，预期返回 `1`；Redis 预期返回 `PONG`。确认数据库只在回环地址监听，再继续启动游戏。后端第一次成功连接 MySQL 时自动创建所需表，不需要额外导入建表 SQL；视频金币计费版另外自动创建 `rtc_charge` 扣费流水表，需要 MySQL 正常连接才能扣费。

以后更换 MySQL 密码时，需要同时修改数据库账户和游戏配置，仅改 `mysql_password` 不会更改数据库中的密码。

这是新库部署。如需保留旧服务器玩家、战绩和会话，切换前应停止旧服写入，备份并恢复 MySQL 与 Redis 数据，再启动新服。不要删除数据库数据目录或清空 Redis。

## 4 配置 Agora

```bash
cd /opt/khuzur/server
[ -f .env ] || cp .env.example .env
chmod 600 .env
nano .env
```

填写同一个 Agora 国际版项目的凭证：

```dotenv
AGORA_APP_ID=你的App_ID
AGORA_APP_CERTIFICATE=你的Primary_Certificate
AGORA_TOKEN_PORT=9760
```

启用该项目的 Certificate / Token 鉴权。证书只放在服务端，不提交 Git、不写入 APK。Agora、R2 和聊天管理员参数都使用同一个 `.env`；R2 参数与私有存储桶设置见 [聊天配置](CHAT.md)。已有旧 `.env.rtc`、`.env.chat` 时，先保留其中的已填值并合并到 `.env`，不要用空模板覆盖。数据库连接仍使用 `etc/config`。

通过 `run.sh` 启动时，会同时启动仅监听 `127.0.0.1:9760` 的 Python Token 服务。直接运行 Skynet 二进制不会启动 Token 服务。媒体由 Agora 云服务传输，游戏服务器负责牌桌权限校验和签发 Token。

## 5 前台启动和验证

```bash
cd /opt/khuzur/server
sh ./run.sh
```

日志应出现：

```text
[db] MySQL connected
[wsgate] listening on :9601
[main] khuzur server started
```

如果出现 `using in-memory store`，说明 MySQL 连接失败、已降级到内存存储，不能作为正式部署成功的结果。

另开一个 SSH 窗口：

```bash
curl --fail http://127.0.0.1:9760/health

curl -i --max-time 5 \
  -H 'Connection: Upgrade' \
  -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Version: 13' \
  -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
  http://127.0.0.1:9601/ws
```

预期分别为 `{"ok": true}` 和 `101 Switching Protocols`。WebSocket 握手成功后连接保持打开，curl 可能在 5 秒后超时；判断依据是此前是否收到 `101`。健康检查不代表 Agora 云端鉴权和实际通话已经验证。

## 6 配置开机启动

前台验证成功后按 `Ctrl+C` 停止服务，避免占用端口，再执行：

```bash
id khuzur >/dev/null 2>&1 || sudo useradd --system --no-create-home --shell /usr/sbin/nologin khuzur
sudo chown -R khuzur:khuzur /opt/khuzur

sudo tee /etc/systemd/system/khuzur.service >/dev/null <<'EOF'
[Unit]
Description=Khuzur game server
Wants=network-online.target
After=network-online.target mysql.service redis-server.service
Requires=mysql.service redis-server.service

[Service]
Type=simple
User=khuzur
WorkingDirectory=/opt/khuzur/server
ExecStart=/bin/sh /opt/khuzur/server/run.sh
Restart=always
RestartSec=5
KillMode=control-group
UMask=0077

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now khuzur
sudo journalctl -u khuzur -n 80 --no-pager
```

游戏服务在 MySQL 和 Redis 服务启动后运行。首次部署先完成第 3 步的账户连接检查；重启机器后仍应检查日志中的 `MySQL connected`，不能只看进程是否存活。手动停止数据库会连带停止游戏服务，数据库恢复后再执行 `sudo systemctl restart khuzur`。

常用命令：

```bash
sudo systemctl status khuzur --no-pager
sudo systemctl restart khuzur
sudo journalctl -u khuzur -f
```

## 7 手机通过 IP 测试

云安全组和系统防火墙放行 TCP 9601，可先限定测试网络的公网 IP。不要对公网开放数据库 3306、6379、调试控制台 9600 和 Token 服务 9760。

在 APK 的设置中保存：

```text
ws://新服务器IP:9601/ws
```

重新打开游戏，先验证登录、大厅和进入牌桌。设置中保存的地址优先于 APK 的默认地址；旧 APK 默认仍指向 `54.254.223.5`，不会自动切换到新服务器。

当前语音视频仅支持 Android。两台手机使用不同账号，同桌坐下，分别通过耳机按钮加入通话，再主动打开麦克风和摄像头，确认双向声音和视频。Web 版只能验证游戏连接。

## 8 域名与 Web 页面

域名不是 IP 直连成功的前提。正式对外使用时配置 HTTPS/WSS，避免登录和通话 Token 通过明文连接传输。

### Nginx 反向代理

把域名 A 记录指向新服务器，并放行 TCP 80、443。创建 `/etc/nginx/sites-available/khuzur`，替换示例域名：

```nginx
server {
    listen 80;
    server_name game.example.com;

    root /var/www/khuzur;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /ws {
        proxy_pass http://127.0.0.1:9601;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 75s;
    }
}
```

```bash
sudo mkdir -p /var/www/khuzur
sudo ln -s /etc/nginx/sites-available/khuzur /etc/nginx/sites-enabled/khuzur
sudo nginx -t && sudo systemctl reload nginx
```

软链接已存在时无需重复创建。配置依据：[Nginx WebSocket 代理说明](https://nginx.org/en/docs/http/websocket.html)。

接着使用证书服务或 ACME 客户端为域名签发有效证书，为这个站点开启 HTTPS 443 和证书自动续期。**上面的配置仅提供 HTTP，不会自行生成证书或开启 WSS。** HTTPS 验证通过后，APK 地址改成 `wss://game.example.com/ws`，关闭安全组对公网 9601 的访问。

### 上传 Web

先按第 9 节构建 Web，再在开发电脑上传构建目录。以下为新服务器的通用示例，替换登录用户和 IP：

```powershell
cd D:\khuzur\app
scp -r build/web 登录用户@新服务器IP:~/khuzur-web-upload
```

上述上传目录首次使用时不应已存在；重复发布使用新的上传目录名，避免产生嵌套目录。服务器确认上传目录中有 `index.html` 后复制：

```bash
test -f ~/khuzur-web-upload/index.html
sudo cp -a ~/khuzur-web-upload/. /var/www/khuzur/
sudo chmod -R a+rX /var/www/khuzur
```

浏览器访问 `https://game.example.com/`。只部署 Skynet 后端不会出现游戏网页；看到 `Welcome to nginx!` 表示当前命中了 Nginx 默认站点，需要检查域名、站点配置和静态文件。

HTTPS 页面应连接 `wss://`，不能继续使用旧的 `ws://IP:9601/ws`。浏览器如果曾保存旧服务器地址，也需要在游戏设置中修改。

当前 `kzur.sdg8888.com` 的 HTTPS 配置仍返回连接说明页。要在该域名发布 Web，需在已有 `/etc/nginx/conf.d/khuzur.conf` 的 HTTPS server 块中设置网站 root，并将原来的 `location = /` 和返回 404 的 `location /` 替换为静态文件规则；保留 `/ws` 代理及证书配置，不要再创建同域名的重复 server 块。仅上传文件不会替换当前说明页。

## 9 前端打包命令

以下在 Windows PowerShell 执行，使用已配置的 `wss://kzur.sdg8888.com/ws`。`flutter` 需已加入 PATH；本机也可用 `& E:\soft\flutter\bin\flutter.bat` 替代命令中的 `flutter`。

### Android release 包

```powershell
cd D:\khuzur\app
flutter build apk --release --split-per-abi `
  --dart-define=SERVER_URL=wss://kzur.sdg8888.com/ws
```

按 CPU 架构分别输出 APK，手机只安装其中一个，优先选 ARM64。当前项目的输出目录为：

```text
D:\khuzur\app\build\app\outputs\flutter-apk\
```

| 文件 | 用途 |
| --- | --- |
| `app-arm64-v8a-release.apk` | ARM64 安卓手机，优先使用 |
| `app-armeabi-v7a-release.apk` | 32 位 ARM 安卓设备 |
| `app-x86_64-release.apk` | x86_64 设备或对应模拟器 |

当前 release 构建仍使用测试签名，可安装测试；正式发布需另外配置发布签名和应用 ID。Agora Certificate 不参与前端打包，只保留在服务器。

### Windows Kotlin 增量缓存兼容设置

本机曾因 C 盘依赖缓存和 D 盘项目之间的 Kotlin 增量编译报错，出现 `Could not close incremental caches`。项目 `app/android/gradle.properties` 已配置以下选项，正常使用上面的 Flutter 打包命令即可；代价是 Kotlin 后续编译不使用增量缓存。

```properties
kotlin.incremental=false
kotlin.compiler.execution.strategy=in-process
```

旧 checkout 尚未包含该配置时，也可使用以下 Gradle 命令，为本次构建传入同样的设置，并显式指定服务器地址：

```powershell
cd D:\khuzur\app\android
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$khuzurServerDefine = [Convert]::ToBase64String(
  [Text.Encoding]::UTF8.GetBytes('SERVER_URL=wss://kzur.sdg8888.com/ws')
)

.\gradlew.bat --no-daemon `
  '-Pkotlin.incremental=false' `
  '-Pkotlin.compiler.execution.strategy=in-process' `
  '-Psplit-per-abi=true' `
  '-Ptarget-platform=android-arm,android-arm64' `
  '-Ptree-shake-icons=true' `
  "-Pdart-defines=$khuzurServerDefine" `
  assembleRelease
```

此备用命令只生成两个 ARM 包，输出目录不变。其他电脑请按实际安装位置调整 `JAVA_HOME`。直接调用 Gradle 前，项目须已成功完成 Flutter 依赖解析。

### Web release 版

```powershell
cd D:\khuzur\app
flutter build web --release `
  --dart-define=SERVER_URL=wss://kzur.sdg8888.com/ws
```

输出目录为 `D:\khuzur\app\build\web`。将其中全部文件上传到 Nginx 网站目录，具体见第 8 节。Web 支持打牌，当前不支持 Agora 语音视频。

### 已安装客户端的地址

`--dart-define` 修改的是此次构建的默认值，不会覆盖用户此前保存的服务器地址。若 APK 或浏览器曾配置旧 IP，需要在游戏设置中重新保存 `wss://kzur.sdg8888.com/ws`，再重新打开游戏。

## 10 更新与连接排查

更新前备份配置和数据，检查服务器本地修改，确认新版本兼容现有数据。拉取代码后更新子模块、重新编译 Skynet，再重启 `khuzur`。上面的目录已交给服务用户管理，更新需要使用具有相应权限且具备 GitHub 读取权限的部署账号。

| 现象 | 检查方向 |
| --- | --- |
| 9601 端口不通 | 游戏进程、监听端口、云安全组、系统防火墙 |
| TCP 能连上但没有 WebSocket 101 | 先从服务器本机测 `/ws`；查看 Skynet 和代理日志，不能仅凭 TCP 成功判断服务正常 |
| 握手成功但大厅进不去 | 登录响应、Redis、MySQL，是否出现内存降级或异常日志 |
| 电脑能连，手机不能连 | 手机设置保存的地址、Wi-Fi 与移动网络差异、访问来源限制 |
| 大厅正常，通话提示不可用 | 新后端是否部署、`.env` 是否存在、是否通过 `run.sh` 启动、9760 健康检查 |
| HTTPS Web 页面无法连接游戏 | 客户端是否使用 WSS、证书是否有效、Nginx 是否配置 Upgrade 请求头 |
| 换服务器后仍连接旧 IP | 设置中保存的地址优先于构建时默认地址；修改并重启客户端 |

相关说明：[开发说明](DEV.md)、[Agora 接入与测试](agora.md)。
