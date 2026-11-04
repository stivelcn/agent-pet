# 合并项目清理记录 · 2026-11-03

本次在确认范围并完成外部备份后执行。目标是只维护合并后的 macOS AgentPet，删除无运行入口的旧实现及独立平台/网站项目；不改变现有使用方式，不重新设计架构。

## 结果

| 项目 | 清理前 | 清理后 |
| --- | ---: | ---: |
| 生产 Swift 文件（Sources + AgentSpeedCore） | 279 | 206 |
| 其中 AgentSpeedCore Swift 文件 | 151 | 88 |
| 回归测试 | 623 | 593 |

清理清单包含 364 个旧源码/资源/文档/工具文件（其中包含被新基线替换的旧测试清单）。29 项旧构建目录条目移出或归档清理。生成缓存会随新构建重新增长，这些数字不是磁盘永久节省承诺。

### 移除的独立内容

- Windows/Linux Tauri 客户端及相关 CI。
- 旧官网、落地页、Cloudflare 网站服务、网站专用静态 manifest 数据及页面发布流程。
- 旧宣传图、公告/网站更新脚本、过期 DMG 背景资源。
- 旧 appcast、重复的上游多语言 README、早期网站/产品设计文档。
- 针对旧应用路径发送模拟事件的历史冒烟脚本。

客户端的在线宠物浏览/下载入口保留，运行时仍可能联网；删除本地网站实现并不等于删除客户端功能。

### 移除的生产代码

- 未使用的捐赠页及二维码资源、旧额度视图、旧项目宠物配置视图、旧动作特效。
- 无运行入口的 NativeUsageProbe / OpenUsageClient / UsageVisibility / LimitFormat，以及其专属的 jcode OAuth 解析器。
- 已被静止/眨眼动画方式替代的 PetBindings / PetBindingsStore。
- 速度核心中的流量采样、网络价格/汇率同步、个人资料/报表上传、独立历史服务、更新客户端和演示工具。

保留项目宠物实际设置入口、当前所有会话/统计功能、所有所需日志源适配器及速度引擎依赖的共享类型。保留的 88 个速度 Swift 文件及 CZstd 文件内容与清理前一致。火焰、速度桥接、桌宠主体和用户数据身份没有修改。

### 为什么测试减少 30 个

这是功能退休，不是为了消除测试失败：

- 22 个测试仅覆盖停用的原生/本地订阅额度探测、显示、重置时间和服务丢失状态。
- 5 个测试仅覆盖该探测链路专用的 jcode OAuth 解析器。
- 3 个测试仅覆盖旧动作绑定默认值。

对应生产实现无运行入口，专属测试随实现一起退休。有效的 `oldSavedActionBindingsCannotReplaceTheRestingLoop` 回归保留，改用隔离的旧格式 JSON 偏好样本，不为测试继续打包旧生产存储器。用户旧偏好没有删除。

原迁移期的 `Tests/legacy-test-inventory.json` 替换为 `Tests/test-inventory.json`，覆盖清理后全部 593 个回归方法。守卫脚本继续阻止静默丢失基线测试。

## 验证

- 清空原 `.build/` 后重新构建成功。
- `scripts/test.sh`：**424 个核心测试 + 169 个应用测试 = 593 个全部通过**。
- Debug 原生 arm64 应用打包成功。
- Release universal 应用打包成功，确认包含 arm64 和 x86_64。
- 两个应用包均通过 `codesign --verify --deep --strict`；应用标识、最低系统版本、图标、本地化和许可证内容正确。
- 应用不再含废弃的捐赠资源 bundle；动态依赖为系统框架/运行时，不依赖项目内的旧构建库。
- Shell 语法、测试清单、文档本地链接和 `git diff --check` 检查通过。
- 编译仍有本机 CLT/编译器的非阻断提示；未为清理而改动系统工具链或关闭诊断。

本次没有重新制作 DMG、进行公证、上传产物或执行真实 UI/多屏/客户端接入验收。双架构构建通过不等于已在 Intel Mac 实机运行验收。

## 运行与数据保护

- 当前开发应用进程没有退出/重启；其应用包文件哈希与清理前完全一致。
- 用户数据、偏好 suite、Bundle ID、配置键、客户端回调路径没有修改。
- `.git/` 和原有暂存状态保留；没有提交、推送或重置 Git。
- 新验证包只放在项目外的 `verification/`，没有启动或覆盖当前包。

打包脚本新增可选的绝对输出目录参数，方便以后在不替换现有应用的情况下验证。默认路径、名称和身份保持不变。

## 备份与证据

本机备份目录：

`/Users/wangyuchen/Documents/AIcoding_project/agent_pet_backups/cleanup-20261103-174046/`

- `project-before-cleanup.tar.gz`：清理前完整源码，包括 `.git`、未提交/未跟踪文件；不含编译缓存和另行保存的 build。
- `build-before-cleanup.tar.gz`：原 build 内容，包括旧应用、安装包、验证日志和集成备份。
- `embercat-integration-backup-20261103-171511/`：原集成前备份，完整移到项目外。
- `SHA256SUMS`：两个归档的校验值；归档目录读取已验证。
- `removed-source-files.json` / `retired-tests.json` / `vendor-audit.json`：明确的清理范围。
- `clean-test.log` / `package-check.log` / `release-universal-check.log`：验证日志。
- `package-verification.json` / `cleanup-summary.json`：结构化结果。

如需恢复，先解压到新目录核对，不要直接覆盖已有新改动的工作区或 `.git`。原有大段阶段验证记录也保留在源码快照中，当前开发说明已经整理到根 README、LOCAL_DEVELOPMENT 和 docs。
