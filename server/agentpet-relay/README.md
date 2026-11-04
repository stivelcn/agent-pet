# AgentPet 双人传话中转

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

**其他站点、程序和配置不归本服务管理，禁止删除或覆盖。**

## 配对与传递

1. 创建者获得服务器用安全随机数生成的 6 位码，A–Z/0–9，至少一个字母和一个数字。
2. 加入者输入配对码，去首尾空白、不区分大小写；创建者确认后才配对。有效期 10 分钟，仅限两台安装实例，每台同时一个关系。
3. 配对码用后失效；后续认证使用每设备随机令牌，服务端仅保存 SHA-256，Mac 凭据存钥匙串，不放 URL、偏好或消息 JSON。
4. 消息最多 20 个扩展字素簇；同时限制 UTF-8 字节数、控制字符和请求体。图标仅限协议中的 6 个预设 ID。
5. SQLite 持久排队；客户端本地原子保存后才发 delivered。关闭气泡发 handled；回复入库与原消息 handled 是同一事务。已接收不等于用户已处理。
6. 重试带原 clientID，服务器去重且拒绝同 ID 换内容。断开或换人后不重定向旧待发消息。解除配对不删除未读记录。
7. WSS 仅通知有变化，REST 同步状态；客户端另有 20 秒补偿同步、指数退避重连。休眠/退出不强制唤醒电脑。

注册、配对猜码、邀请、发送和认证请求有频率限制；每人最多 200 条未处理消息。未读消息不按时间自动删除；服务端保留消息记录，客户端只展示最近 50 条发送记录中的最近 5 条。后续如增加保留策略，必须明确告知用户，不能静默丢弃未读。

传输是 HTTPS/WSS，**不是端到端加密**；服务器管理员可以访问数据库。中转不记录消息内容、认证令牌或 URL 查询凭据。不要将数据库/备份提交 Git。

## 运维

```bash
systemctl status agentpet-relay
journalctl -u agentpet-relay -n 50 --no-pager
curl -fsS http://127.0.0.1:7831/healthz
/usr/local/nginx/sbin/nginx -t
```

依赖锁定在 `requirements.lock`，升级只使用本服务 `.venv/bin/pip`，不改系统 Python/Node 或其他应用环境。更新源代码前保留旧版本，更新 SQLite 前使用在线备份 API，不直接复制活动中的单个 `.sqlite3` 文件（WAL 可能仍有数据）：

```bash
# root 执行；备份含私人消息，目录必须仅管理员可访问。
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

回退：只停本服务、移除本次新增 include 行并校验、平滑 reload Nginx；不整文件覆盖可能已有新改动的 Nginx 主配置。保留数据库与备份，不删除用户消息或现有项目。

## 本地验证（macOS）

在仓库根目录：

```bash
python3 -m venv build/relay-venv
build/relay-venv/bin/pip install -r server/agentpet-relay/requirements.lock
build/relay-venv/bin/python -m unittest discover -s server/agentpet-relay -v
./scripts/test.sh
```

显式线上冒烟（创建两个 QA 身份，不使用真实应用凭据；不输出或保存令牌）：

```bash
build/relay-venv/bin/python server/agentpet-relay/smoke_test.py
AGENTPET_RELAY_LIVE_TESTS=1 ./scripts/test.sh --filter PetRelayIntegrationTests.liveHTTPSRoundTripWhenExplicitlyEnabled
```
