# LuMate · 噜伴：本地开发与验证

界面名称为“LuMate · 噜伴”，开发版为“LuMate · 噜伴（开发版）”。应用包为 `LuMate.app` / `LuMate Dev.app`。当前维护范围是 LuMate macOS 桌宠，基于 AgentPet 并集成 EmberCat 刘海火焰/实时速度。内部可执行文件、Bundle ID、数据目录、偏好键和 `AGENTPET_*` 环境变量保持原标识。

## 1. 日常命令

在项目根目录运行：

```bash
./scripts/dev.sh run       # 构建成功后，只重启本仓库的开发实例
./scripts/dev.sh build     # 构建并替换默认开发包，不启动
./scripts/dev.sh stop      # 只停止本仓库路径下的开发实例
./scripts/test.sh          # 所有回归测试
./scripts/test.sh --filter EmberCatIntegrationTests
```

默认产物为 `build/LuMate Dev.app`。`run` 不是热更新，但不需要打 DMG 或重新安装。构建失败不会停止当前实例；脚本按完整可执行文件路径识别实例，不按通用进程名批量退出应用。

**只验证打包、不替换当前应用包**时，指定独立的绝对输出目录：

```bash
./scripts/build-app.sh debug native /tmp/agentpet-package-check
```

打包脚本先在临时目录完成资源复制与本地签名校验，成功后才替换目标包。它不启动应用。默认开发包与当前运行实例有关，不要在未经确认时覆盖或重启。

## 2. 工具链

运行最低要求为 **macOS 14**，使用 Swift 6 和匹配的 macOS SDK。

构建统一经过 `scripts/swiftpm.sh`：

- 正常环境使用当前选择的工具链，不安装或修改 Xcode/Command Line Tools。
- 升级 CLT 后若 SwiftPM private/public interface 版本不一致，仅在 `build/toolchain-compat/` 生成项目级 VFS 映射和缓存。
- 本机已确认的 CLT 27 缺少 `SwiftUIMacros` 情况下，若已有 macOS 26.5 SDK，则仅对本项目选用它并输出提示。
- 可通过 `AGENTPET_SDK_PATH=/绝对路径/SDK` 显式选择 SDK；不下载 SDK，不修改 `xcode-select`。
- 裸 `swift build` / `swift test` 不包含这些兼容处理，请优先使用项目脚本。

## 3. 数据与配置身份

| 项目 | 本地正式版 | 开发版 |
| --- | --- | --- |
| Bundle ID | `local.agentpet` | `local.agentpet.dev` |
| 偏好 suite | `local.agentpet.preferences` | `local.agentpet.dev.preferences` |
| 文件数据目录 | `~/.agentpet-local/` | `~/.agentpet-local-dev/` |
| 默认应用包 | `build/LuMate.app` | `build/LuMate Dev.app` |

宠物文件、历史归档、socket 等保存在数据目录；部分设置、累计养成和项目用量由 macOS UserDefaults 持久化，不能只备份数据文件夹就认为包含全部使用状态。

不自动导入原版 AgentPet 数据。保留原版安装不代表共享存储。

### 从 AgentPet Local 升级到 LuMate

只改对外品牌，不迁移或清空数据；同一构建类型继续使用原有 Bundle ID、偏好域、数据目录及钥匙串标识。开发版与正式版仍不共享进度。

应用包路径已经改变，旧 Hook 不会被静默覆盖。已有连接请先在**旧版设置中断开编程助手连接**，退出旧版，再启动同类型 LuMate 并重新连接；如客户端提示外部命令信任，核对新路径并自行确认。旧应用已移走时，可暂时从原路径打开旧包完成断开；不要直接覆盖整个客户端配置或关闭安全机制。登录启动项如仍指向旧包，可在 LuMate 中关闭再开启并按 macOS 提示确认。

`dev.sh run/stop` 只会识别本仓库 `build/LuMate Dev.app` 与旧 `build/AgentPet Local Dev.app` 两个完整路径，不按进程名批量终止，也不删除旧包。构建或测试不会主动启动应用、迁移 Hook 或改写登录启动项。

### EmberCat 原偏好

仅在首次正常运行合并版时，从 `com.johann.embercat` 只读导入：

- `notchFlamesEnabled`
- `notchFlamePalette`
- `notchFlameAppearance`
- `showsTokenRate`

已有目标值不被覆盖；颜色/外观 JSON 字节保持原样。完成标记为 `agentpet.embercat.imported.v1`。原 EmberCat 的设置不改写；不导入猫、Dock、更新器等偏好。

自定义数据目录/偏好 suite 或禁用 EmberCat 时，不执行这项导入。开发版和正式版的偏好独立，不能假定两者已经相互迁移。

## 4. 客户端连接与隔离

正常启动会检测已安装的编程助手，并在事件接收器启动后配置连接。配置写入按客户端格式合并，保留其他回调；写入前备份。冲突或解析失败不强行覆盖。备份位于当前数据目录的 `config-backups/`。

仅检查界面、不写真实客户端配置：

```bash
AGENTPET_ENABLE_DEV_HOOKS=0 ./scripts/dev.sh run
```

只禁用启动时自动连接、仍允许设置中手动连接：

```bash
AGENTPET_AUTOCONNECT=0 ./scripts/dev.sh run
```

其他变量：

| 变量 | 作用 |
| --- | --- |
| `AGENTPET_DATA_DIR` | 自定义绝对路径的数据目录；空值和相对路径不生效 |
| `AGENTPET_PREFERENCES_SUITE` | 自定义独立偏好 suite |
| `AGENTPET_EMBERCAT_ENABLED=0` | 禁用 EmberCat 实时监测/火焰启动与旧偏好导入 |
| `CODEX_HOME` | 绝对路径时用于 Codex 配置和会话发现 |
| `AGENTPET_METRICS=1` | 可选的本地宠物窗口尺寸日志；写入当前数据目录的 `metrics.log` |

`dev.sh` 显式传递数据目录、偏好、连接和 EmberCat 开关到 LaunchServices。窗口尺寸诊断变量可在直接启动可执行文件的隔离调试环境中使用。

**同一客户端的回调配置不会因为应用分身而隔离。** 不要让多个应用版本争用同一客户端。客户端可能需要重新加载会话；信任确认由用户在客户端完成。应用不修改模型、登录凭据、信任记录或审批规则。

## 5. 自动化测试

`test.sh` 使用 Swift Testing，为本次运行创建临时数据目录和随机偏好 suite，禁用客户端配置、自动连接和 EmberCat 后台启动；结束时仅清理本次临时状态。测试不调用收费模型，不向正在运行的应用发送模拟业务事件。

本机 CLT 若需要 TestingMacros 插件，脚本显式加载已安装插件并禁用 XCTest 发现。无需为此更改系统工具链。

`Tests/test-inventory.json` 记录当前回归基线，`scripts/check-test-inventory.py` 防止静默丢失测试。添加/退休功能时应维护清单并说明原因。2026-11-03 的清理删除的是已经无运行入口功能的 30 个专属测试；当时保留 593 个测试，其中包括旧动作配置兼容和 EmberCat 集成回归，详见 `docs/CLEANUP.md`。2026-11-04 的 Token-only 与图表悬停改动同步更新了测试清单，当前为 **597 项（核心逻辑 421 项、应用逻辑 176 项）**。

测试覆盖不等于系统级验收。通知授权、真实多屏交互、客户端主动回调、长时间运行仍需分别验证；不要把编译通过当作真实 UI 已验收。

## 6. 生成物与备份

- `.build/`：可再生的 Swift 编译缓存；删除后要重新编译。
- `build/toolchain-compat/`：项目级工具链兼容缓存，可由脚本再生。
- `build/*.app`：可能正在使用的应用包；清理前确认，不随意删除。
- `build/*.dmg`：手动分发产物，不是日常开发必需。
- 备份放在项目外，包含未提交和未跟踪文件；不要用 `git reset` 替代备份或清理。

本次清理未改变用户数据目录、偏好键、Bundle ID，也没有重启应用。此前的阶段性截图、日志和集成前备份已移至外部归档，不作为源码继续维护。

## 7. 仍需独立规划的工作

v0.2.0 已移除费用估算的界面、价格表、计算与存储字段；保留 Token 统计、速度和养成，并为近七天图表增加逐日精确数量浮窗。旧 JSON 的额外费用字段会被忽略，不需要清空已有历史。项目日明细的保留策略未在本次调整中改变，所有客户端/第三方服务适配仍需分别验证。版本变化见 `CHANGELOG.md`。

在线宠物浏览和下载仍依赖资源服务，应用并非完全离线。现已内置噜噜和噜妹外观（噜妹仅含待机/呼吸/眨眼），不需要联网下载即可使用；没有新增生成模型接口。未来模型提示词必须放在根目录 `model_prompt/` 的对应接口 Markdown 文件中。

手动 DMG 打包见 `docs/RELEASING.md`；数据流和后续代码入口见 `docs/ARCHITECTURE.md`。


## 宠物档案与外观（2026-11-04）

- `Sources/AgentPetCore/PetCompanion.swift` 定义稳定的宠物身份。`PetController.selectedPetID` 仍是用于窗口渲染的**外观 ID**，不能直接当成养成档案 ID。
- `agentpet.companions.v1` 是新养成存档，单个 JSON 值原子保存版本、当前身份、档案（外观/名字）和完整 `PetCareState`。切换形象不改身份或养成状态；「新建宠物」创建独立 UUID，保留旧档案，可用「当前宠物」切回。
- 首次启动复制 `agentpet.care.v2`（或 v1）和自定义名字，不删除、不覆盖旧键，也不把不同宠物的经验相加。若旧版选中了未养过的外观，会恢复已有养成身份并保留所选外观；其他历史仍保留。存档无法解码或结构无效时停止写入，设置页显示错误，避免用零值覆盖。
- `state(forCompanionID:)` 用于明确的档案；原窗口/项目接口 `state(for:)`、喂食参数仍传外观。解析优先当前穿着该外观的档案，其次已有匹配/旧身份；尚未养过的分项目宠物在实际收到食物时创建独立档案，不修改项目关联设置。同外观有多个档案时当前档案优先。
- 内置资源位于 `Sources/App/Resources/BuiltinPets`。开发的 SwiftPM 使用资源 bundle，打包脚本复制到 `.app/Contents/Resources/BuiltinPets`，移走源码目录仍可加载。有效的同 ID 用户导入包优先，损坏时回退到内置包，内置 ID 禁止在选择器删除。
- 噜妹显式使用 192×208 固定格、六帧和毫秒时长，正常速度一圈 3.2 秒；困倦时等比例减速。老素材仍兼容透明间隙切帧和恒定 FPS。两者均只播放第一行待机，未新增跑跳动作。
- 回退应用版本前先导出当前偏好；旧键只是迁移时快照，旧版不会理解新档案，不能把它当成持续同步的备份。
- `scripts/test.sh` 在临时偏好域/数据目录内检验迁移、换装、重启、新建、喂食路由、内置素材、透明边缘和帧时长；不要给真实用户存档注入测试经验。


## 传话开发与部署

客户端源码：`PetRelay.swift`（协议/本地状态机）、`PetRelayAPI.swift`（HTTPS/WSS/钥匙串）、`PetRelayController.swift`（持久化/队列/重连）、`PetRelayViews.swift`（配对/常驻气泡）、`PetRelayComposerModel.swift` / `PetRelayComposerView.swift`（桌宠旁发送/回复）。不依赖模型接口，不新增提示词或模型密钥。

- 接口：`https://imagepro.ycgod.online/agentpet-relay/`。按安装实例配对，与皮肤和养成档案分离。
- 消息文件：当前数据目录下 `pet-messages.json`（权限 0600）；令牌只在独立 Keychain service 中，不能复制进日志或 JSON。
- 设置页只做配对、昵称与连接管理。发送与回复使用 `PetWindowController.showMessageComposer` 原生 NSPopover，锚定触发它的宠物；Escape/关闭/点击外部不处理消息。输入框绑定原配对 ID，离线待发阻止重复点击，并允许取消重试。
- 测试脚本默认 `AGENTPET_RELAY_ENABLED=0`，使用临时目录和 mock 凭据；不会接触真实钥匙串或中转。显式线上测试命令见服务 README。
- 常驻消息的本机保存失败时不回执；损坏文件保持原样，不覆盖。不自动删除未读，解除配对后仍可手动关闭旧消息。
- 线上服务只监听回环地址，由现有 Nginx 新增独立 location 转发；依赖全装在专用 venv。配置、SQLite 在线备份和回退边界见 `server/agentpet-relay/README.md`。
- 本地包是 ad-hoc 签名，不是已公证发行包。后续更新若 macOS 请求访问此前保存的配对钥匙串项，需要用户本人授权，不绕过系统提示。
