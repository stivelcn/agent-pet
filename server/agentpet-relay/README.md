# LuMate 双人传话中转

`agentpet-relay` 目录、服务名和已部署 API 路径保留兼容标识；品牌改名不修改线上服务或用户消息数据。

这是独立轻量服务，不依赖生成式模型，不读取或上传桌宠养成、Token 历史、AI 配置。

## 当前部署

- 公网 HTTPS/WSS：`https://imagepro.ycgod.online/agentpet-relay/`
- 程序及隔离虚拟环境：`/srv/agentpet-relay/`
- systemd：`/etc/systemd/system/agentpet-relay.service`
- 仅监听：`127.0.0.1:7831`（不要开放公网端口）
- SQLite：`/var/lib/agentpet-relay/messages.sqlite3`（systemd DynamicUser / StateDirectory 管理）
- 新增 Nginx 片段：`/usr/local/nginx/conf/agentpet-relay.location.conf`
- 在原有 `imagepro.ycgod.online` 的 HTTPS server 内，仅新增一行 include。原网站的 location、证书、上游服务不变。
- 原始 Nginx 配置备份：`/srv/agentpet-relay/backups/nginx.pre-relay.conf`。

2026-11-06 已部署协议 2，并从公网验证双方形象、戳戳、抱回去、探头、实时通知和小头像上传。服务端 16 项测试及六小时清理的 30 个边界用例通过；临时测试身份和此次数据库备份已删除。

同日修复发送确认延迟：JSON 响应达到 1 KiB 时按客户端 `Accept-Encoding` 启用 gzip/deflate 压缩；未声明压缩能力的客户端继续收到原始 JSON，WSS 通知不变。历史消息中重复的宠物头像不再全部按原始大小传输。17 项服务端测试通过；临时身份使用 macOS 原生 URLSession 测得同一响应由 179,601 字节降至 24,572 字节，请求从 2.32 秒降至 0.47 秒，解压后内容一致。线上程序更新即可生效，v0.2.3 客户端无需重装；实际耗时仍取决于网络和消息数量。

**其他站点、程序和配置不归本服务管理，禁止删除或覆盖。**

## 配对与传递

1. 创建者获得服务器用安全随机数生成的 6 位码，A–Z/0–9，至少一个字母和一个数字。
2. 加入者输入配对码，去首尾空白、不区分大小写；创建者确认后才配对。有效期 10 分钟，仅限两台安装实例，每台同时一个关系。
3. 配对码用后失效；后续认证使用每设备随机令牌，服务端仅保存 SHA-256，Mac 凭据存钥匙串，不放 URL、偏好或消息 JSON。
4. 消息最多 20 个扩展字素簇；同时限制 UTF-8 字节数、控制字符和请求体。图标仅限协议中的 6 个预设 ID。
5. SQLite 持久排队；客户端本地原子保存后才发 delivered。关闭气泡发 handled；回复入库与原消息 handled 是同一事务。已接收不等于用户已处理。
6. 重试带原 clientID，服务器去重且拒绝同 ID 换内容。断开或换人后不重定向旧待发消息。解除配对不删除未读记录。
7. WSS 仅通知有变化，REST 同步状态；客户端另有 20 秒补偿同步、指数退避重连。休眠/退出不强制唤醒电脑。
8. 协议 2 声明 `pet-interactions-v1`；`POST /v1/device/pet` 保存名字、内置形象 ID 或小尺寸 PNG。`pair.peerPet` 只分享给当前配对，消息 `senderPet` 固定发送时形象。PNG 限 128×128、32 KiB，校验块 CRC、像素解压长度；请求上限 48 KiB。
9. 动作 `poke/hug/peek` 与文字/图标三选一，双方须先同步新版形象。动作有效 30 秒，三秒内不能再次发动作，冷却查询持久消息记录，服务重启后仍生效。重试去重先于过期检查；原消息入库后即使响应丢失也不会重复发送。回击与处理原消息同一事务。

注册、配对猜码、邀请、发送和认证请求有频率限制；每人最多 200 条未处理消息。未读消息不按时间自动删除；客户端只展示最近 50 条发送记录中的最近 5 条。线上另有 `agentpet-relay-cleanup.timer`，北京时间每天 00:00、06:00、12:00、18:00 只清理已处理超过六小时的消息；未处理消息、设备和配对保留。清理只判断 `handled` 处理时间，不区分文字、表情、戳戳、抱抱、探头或后续新增互动；仅送达或动画过期不会触发删除。本次更新保留该清理规则。

传输是 HTTPS/WSS，**不是端到端加密**；服务器管理员可以访问数据库。中转不记录消息内容、认证令牌或 URL 查询凭据。不要将数据库/备份提交 Git。

## 运维

```bash
systemctl status agentpet-relay
journalctl -u agentpet-relay -n 50 --no-pager
curl -fsS http://127.0.0.1:7831/healthz
/usr/local/nginx/sbin/nginx -t
```

依赖锁定在 `requirements.lock`，升级只使用本服务 `.venv/bin/pip`，不改系统 Python/Node 或其他应用环境。更新源代码前保留旧版本，更新 SQLite 前使用在线备份 API，不直接复制活动中的单个 `.sqlite3` 文件（WAL 可能仍有数据）。按当前用户设置，数据库备份仅供本次升级临时校验，验收通过后删除，不长期保留聊天正文：

```bash
# root 执行；临时备份含私人消息，目录仅管理员可访问，验收后删除此文件。
python3 - <<'PY'
import sqlite3, time
from pathlib import Path
out = Path('/srv/agentpet-relay/backups') / ('messages-' + time.strftime('%Y%m%d-%H%M%S') + '.sqlite3')
with sqlite3.connect('/var/lib/agentpet-relay/messages.sqlite3') as src:
    with sqlite3.connect(out) as dst:
        src.backup(dst)
out.chmod(0o600)
PY
```

回退时优先还原代码并保留数据库，避免丢失升级后收到的消息。旧代码的注册语句须使用显式列名 `INSERT INTO devices(id,token_hash,name,created)`，才能兼容增列后的数据库。Nginx 只还原本服务独立配置片段并校验、平滑 reload，不整文件覆盖主配置。

协议 2 保留原端口；Nginx 的 `/agentpet-relay/` 独立片段须将请求体上限从 8k 调到 48k，以支持小头像。先执行上面的临时 SQLite 在线备份，保留旧 `relay.py`，再原子替换代码并重启 `agentpet-relay`。启动会重复安全地增加 `devices.pet`、`messages.gesture/expires/sender_pet` 列；旧客户端、凭据和未读记录保留。核验 `/healthz` 的 `protocol: 2` 与能力声明，并用两个临时身份测试形象、动作和回击；成功后删除临时数据库备份。此仓库的本地打包不会自动执行部署。

## 本地验证（macOS）

在仓库根目录：

```bash
python3 -m venv build/relay-venv
build/relay-venv/bin/pip install -r server/agentpet-relay/requirements.lock
build/relay-venv/bin/python -m unittest discover -s server/agentpet-relay -v
./scripts/test.sh
```

本机隔离中转运行后，可指定 `AGENTPET_RELAY_TEST_URL=http://127.0.0.1:端口/ ./scripts/test.sh --filter isolatedLocalRelayRoundTripSynchronizesBothPetsAndReplies`。它只连接 localhost，临时创建双方身份，不用应用钥匙串或真实配对。离屏截图可指定 `AGENTPET_UI_SNAPSHOT_DIR`，测试不显示窗口。

显式线上冒烟（创建两个 QA 身份，不使用真实应用凭据；不输出或保存令牌）：

```bash
build/relay-venv/bin/python server/agentpet-relay/smoke_test.py
AGENTPET_RELAY_LIVE_TESTS=1 ./scripts/test.sh --filter PetRelayIntegrationTests.liveHTTPSRoundTripWhenExplicitlyEnabled
```
