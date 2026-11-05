# LuMate：手动构建 macOS 分发包

日常开发使用 `scripts/dev.sh`，不需要 DMG。手动打包：

```bash
./scripts/release.sh native       # 当前 Mac 架构
./scripts/release.sh universal    # arm64 + x86_64
```

版本读取 `scripts/AppInfo.plist`（当前为 `0.2.2`）；变更记录见根目录 `CHANGELOG.md`。输出为 `build/LuMate.app` 和 `build/LuMate-<版本>-<架构>.dmg`。正式版本的数据与开发版隔离，不会因为从开发版切换为正式版就自动迁移。

脚本只在本机生成产物，不上传、不更新 appcast、不使用上游凭据。GitHub 的 macOS workflow 仅支持手动产生构建 artifact，不随标签发布公开 Release。

## 签名

默认是本地 ad-hoc 签名，并在替换应用包前校验。可选使用自己的已配置 Developer ID 和公证 profile：

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="your-notary-profile" ./scripts/release.sh universal
```

`NOTARY_PROFILE` 必须与 `SIGNING_IDENTITY` 一起设置。开发脚本不删除隔离属性、不关闭系统安全功能；本地签名校验通过不等于已经通过 Apple 公证。

## 分发内容与检查

- 应用包包含图标、本地化资源、AgentPet/Agent Speed/zstd 的许可证和来源说明。
- DMG 附带原项目 `LICENSE`；应用内同时包含 `THIRD_PARTY_NOTICES.md`，不能只阅读根许可证就忽略第三方来源。
- EmberCat 火焰源码单独记录在 `THIRD_PARTY_NOTICES.md`，不能视为由根目录 MIT 或其图片素材的 CC0 声明覆盖；再次分发时需核实上游对这些源码的适用条款。
- 发布前运行 `scripts/test.sh`，检查包签名和两种架构，另行完成真实 UI/权限/客户端接入验收。
- 不把用户数据目录、偏好备份、客户端配置或密钥带入分发包。

## GitHub Release 与应用内更新

当前客户端从 `https://api.github.com/repos/stivelcn/lumate/releases/latest` 按用户操作检查正式版本，不取草稿/预发布，不自动安装。打包本身不上传，不修改现有手动 workflow 的发布权限。

发布约定：

1. 更新 `scripts/AppInfo.plist` 中两个版本字段和 `AppUpdateController` 的裸二进制开发回退版本，维护变更记录并运行测试。
2. 使用 `./scripts/release.sh universal` 生成 `LuMate-<版本>-universal.dmg`；也支持明确标注 `arm64` 或 `x86_64` 的包。不识别无法判断架构的 `native.dmg`。推荐发布通用包。
3. 自行创建本仓库的正式 GitHub Release，标签使用 `v<版本>`；附件名称必须与版本一致，并提供 GitHub API 的 `digest: sha256:...`（GitHub 为新上传附件生成）。缺少有效摘要的包不可在应用内下载/安装。可附 `SHA256SUMS.txt` 供手动核对，但不能替代 API 摘要。
4. DMG 根目录必须包含 `LuMate.app`，Bundle ID 保持 `local.agentpet`，版本必须与标签一致，不能上传开发包。已采用 Developer ID 的版本必须延续同一 Team ID；面向其他 Mac 建议同时签名、公证。
5. 本轮代码不会自动创建标签、上传附件或发布 Release。v0.2.0 用户首次升级需手动安装；后续高版本才可通过应用内更新。

安装器会二次核对下载大小/SHA-256、版本、Bundle ID、系统要求、架构和签名，再将新版先复制到安装目录所在文件系统。两次同卷重命名保留旧包，替换失败恢复旧包；授权取消不退出应用。重启辅助进程等待原进程退出后从原路径启动新版，若启动命令立即报错则尝试旧版备份并提示；不能检测启动后崩溃或所有 Gatekeeper 拦截情况，发生此类问题需从保留的旧包手动恢复。旧包不自动删除，避免误删唯一可恢复副本。

用户数据安全边界：仅替换应用本体；保持 `local.agentpet.preferences`、原数据目录、钥匙串 service 不变，不复制开发数据到正式域。安装前保存养成/消息并同步偏好，保存失败终止；正在输入的传话需先发送或关闭。下载的 DMG 保留在「下载」，可自行清理。更新不会关闭 Gatekeeper、删除 quarantine 或绕过钥匙串授权。

验证包含隔离目录内真实签名应用/DMG的挂载、校验、卸载、替换与回退，不会更新或重启开发者当前安装的 LuMate。管理员授权、Apple 公证/安全提示、真实安装后重启仍需用测试 Mac 单独验收。
