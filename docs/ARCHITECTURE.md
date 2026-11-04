# LuMate · 噜伴：模块与数据流

LuMate 是对外品牌；`AgentPetCore`、`agentpet` 可执行文件、Bundle ID、偏好键、环境变量与数据目录保留既有标识，以兼容存量数据和客户端集成。

## 应用入口

`Sources/App/AppEntry.swift` 是唯一可执行入口：根据参数分派 `hook`、`run` CLI，或启动 macOS 应用。两条 CLI 分支仍用于现有客户端集成，不是另一个待删除的应用。

`AgentPetApp.swift` 协调应用生命周期；`AppDaemon.swift` 负责会话事件。菜单栏由 `StatusBarController.swift` 和 `MenuBarContentView.swift` 管理。LuMate 设置由 `SettingsWindowController.swift`、`SetupView.swift` 等维护。

## 两条互不重复记账的数据流

1. **LuMate 业务流**：客户端事件/日志 → `AgentPetCore` 会话模型 → `AppDaemon` / `ProjectUsageStore` / 养成与历史 → 桌宠、完成提醒、历史报表和日历热力图。
2. **EmberCat 实时流**：日志源适配器 → `AgentSpeedCore.LiveMonitor` → `SpeedStore` → `EmberCatIntegration` → 同一个菜单栏速度文本和 `NotchFlameController`。

实时速度桥接不写 LuMate 的使用历史或养成账本，不安装回调，不启动上传服务。不同统计口径不可未经设计就混合累计。

## EmberCat 适配边界

`Sources/App/EmberCat/` 共 12 个文件，包含桥接、偏好导入、设置窗口、火焰渲染/着色器、显示器选择、编辑器和预览控制器。

菜单栏新增的是 LuMate 面板中的 EmberCat 设置入口，不新建第二个状态栏图标。不包含原上游的猫、玛奇玛、Dock 陪伴、爪印和自动更新器。

`EmberCatPreferences.swift` 的导入白名单及标记键是兼容边界；不得为清理而随意改名。设置窗口与原生预览共用应用激活状态管理。

## 速度依赖为什么没有只剩两三个文件

`Vendor/AgentSpeedCore/` 是按实时监测依赖裁剪的 **82 个 Swift 文件**，不是完整上游。保留：

- 各日志源的解析、发现、读取、文件监听和实时速度计算。
- 快照、工作状态、估算占比、时间窗口和内存统计。
- 引擎引用的日报 token 聚合、报表事实模型和账本类型。
- 压缩/SQLite 等日志读入所需支持；zstd C 代码位于 `Vendor/CZstd/`。

`Reporting`、`History` 下仍有少量共享实现被实时引擎直接引用。**目录名不代表有上传或历史扫描服务正在运行，不能整目录删除。** 当前桥接仅启动本地 `LiveMonitor` 和 `SpeedStore`。

已删除流量采样、网络价格/汇率同步、账户资料/报表上传、独立历史数据库服务、更新客户端和演示驱动。所有保留的日志源适配器不因本机暂时没使用某个客户端而删除。

2026-11-04 已移除费用预估界面、持久化字段及完整价格表/费用计算链路；旧用量记录中的额外字段会被忽略，token 与会话历史继续保留。实时速度的 token 估算占比不属于金额预估，仍然保留。

更新上游时需重新核对依赖，运行干净构建和集成测试，并同步 `Vendor/AGENT-SPEED-UPSTREAM.md`、许可证和 `THIRD_PARTY_NOTICES.md`。

## 宠物与项目设置

项目宠物分配仍由 `ProjectPetSettings.swift` 配合 `SetupView.swift` 的实际设置入口实现；删除的是没有调用者的旧 `ProjectPetsView.swift`。

当前宠物使用静止/眨眼帧循环，不再读取旧的动作绑定存储。`QuietPetAnimationTests` 使用隔离的旧格式配置样本验证兼容性；不为测试保留已经停用的生产实现，也不删除用户旧偏好。

## 开发保护

- 根目录 `Package.swift` 是实际构建图；无需 npm、Rust 或旧网站工具链。
- `Localizations/` 和应用图标由打包脚本复制。当前没有 SwiftPM 独立资源 bundle。
- `Tests/test-inventory.json` 是合并后回归基线。
- 生成物不进源码；用户数据和配置不作为清理对象。
