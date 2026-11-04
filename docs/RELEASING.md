# LuMate：手动构建 macOS 分发包

日常开发使用 `scripts/dev.sh`，不需要 DMG。手动打包：

```bash
./scripts/release.sh native       # 当前 Mac 架构
./scripts/release.sh universal    # arm64 + x86_64
```

版本读取 `scripts/AppInfo.plist`（当前为 `0.2.0`）；变更记录见根目录 `CHANGELOG.md`。输出为 `build/LuMate.app` 和 `build/LuMate-<版本>-<架构>.dmg`。正式版本的数据与开发版隔离，不会因为从开发版切换为正式版就自动迁移。

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
