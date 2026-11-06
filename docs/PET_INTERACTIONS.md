# 宠物互动动作

## 使用

「设置 → 传话 → 预览宠物互动」提供噜噜、噜妹的戳戳、被戳、抱抱、探头。每次播放约两秒，完成后切回原待机；再次点击会从第一帧重播，关闭预览会停止计时器。关闭应用动画或启用系统「减弱动态效果」时按钮停用。

配对后，单击桌宠可在发送框里看到对方的实际形象，并发送「戳戳、抱抱、探头」。设置的传话页也显示对方形象。噜噜、噜妹使用应用内自带的同款动作；导入的宠物分享 96×104 透明头像，来访时显示头像及互动符号。

收到新互动时，对方宠物短暂来访约两秒，本地宠物同步播放被戳、抱抱或探头，然后恢复原待机。互动消息保留在未读气泡；点「戳回去 / 抱回去」发送成功后才处理该条消息，其他未读保留。失败可以重试，取消不会处理来信。

关闭动画、启用 macOS「减弱动态效果」或桌宠不可见时不播放来访。互动 30 秒过期，离线后仍保留文字摘要，重连不连续补播旧动作。待发互动超过 30 秒不会重试，普通传话继续使用原持久队列。连续互动间隔至少三秒。

## 形象与协议

新版中转在同步数据中声明 `pet-interactions-v1` 能力。客户端在主动配对后同步宠物名字、内置形象 ID 或小头像；选中形象/名字变化最迟在下一次 20 秒同步更新。只同步改动；旧中转或未更新的对方会显示提示，原文字和图标消息仍可使用。

新增 `POST v1/device/pet`，消息支持 `gesture`、`expiresAt`，并保存发送当时的 `senderPet`。只允许 `poke/hug/peek`，每条消息必须在文字、图标、动作中三选一。客户端和服务端都校验配对 ID，回击不能转给后来配对的人。服务端校验 PNG 格式、尺寸和解压长度，最大 128×128 / 32 KiB；客户端只上传 96×104 单帧，不上传整张动作图或宠物档案。

来访 ID 在显示前原子保存，重启、重复同步和丢失 HTTP 响应都不会重播。来访消费与未读处理相互独立；持久化失败时不播放、不确认。服务端为旧客户端提供动作文字摘要。数据库使用可重复的增列迁移，保留已有凭据、配对和消息。

线上中转已于 2026-11-06 更新并通过公网验证，双方需安装新版客户端。所有表情和互动沿用统一清理规则：已处理超过六小时后，在下一轮定时清理中删除；未处理消息保留，动作过期不会删除消息。部署步骤见 `server/agentpet-relay/README.md`；本地测试及打包不会自动部署线上服务。

## 资源与播放

每个内置宠物增加可选的 `interactions.json` 和透明 `interactions.png`。后者为 1152×832，六列四行，每格 192×208。清单版本为 1，`clips` 用动作名称对应行号和 `frameDurationsMS`。旧包、缺失或损坏的附加清单不会影响原待机包加载。

`PetInteractionLibrary` 限制同目录图片、有效行号、每组 2～24 帧、单帧 20～2000 毫秒和总时长不超过四秒。`PetInteractionPlayer` 使用每次播放的唯一 ID，旧动画完成回调不能结束新动画。`ImageSpriteView` 保留原有循环默认值，额外支持播放一次；任务状态仍只改变原来的待机节奏，不自动播放互动。

## 提示词与重制

- 模型：用户指定的 `gpt-image-2.6-flare`，服务为 `https://api.aimindsky.com/v1/images/edits`。
- 模板、身份约束、动作顺序在 `model_prompt/images_edits.md`；每组完整请求文本在 `model_prompt/pet_interactions/{pet}/{action}/images_edits.md`。提示词不写在 Python/Swift 代码中。
- 后续生图使用 `/Users/wangyuchen/.codex/skills/aimindsky-image/scripts/aimindsky_image.py edit`，凭据从 `AIMINDSKY_API_KEY` 或 macOS 钥匙串服务 `codex-aimindsky-image` 读取。不得把 Key 写入项目或日志。
- 请求使用原待机首格参考、`size=1536x1024`、`quality=high`；编辑接口不加 `output_format`。保留服务返回的真实透明通道；如果返回蓝幕则移除背景。

制作辅助脚本是 `scripts/prepare-pet-interactions.py`，需使用 Codex 工作区自带的 Python/Pillow：

1. `prepare` 从已有待机图提取参考，并从 Markdown 生成八组提示词和忽略目录 `output/pet-interactions/jobs.json`。这一步不调用模型。
2. 用 Aimindsky 技能分别生成每组完整六帧，保存为 `output/pet-interactions/generated/{pet}-{action}.png`。每次生成后检查角色、动作、间隔和完整性，不自动重试收费 POST。
3. `assemble` 只处理已有成图：清理背景与分离小杂点、使用每组统一比例和脚底锚点组装附加图。它不绘制或推算新的动作。
4. 对两张最终图分别运行 hatch-pet 的 `despill_chroma_edges.py` 一次，蓝幕键为 `#0000FF`，确认报告 `ok: true` 与 `alpha_preserved: true`。不要重复去色。
5. `review` 从最终打包的像素重新生成八个 GIF、总览图和双宠物动图 `output/pet-interactions/preview.gif`，做最终视觉检查。

当前生成与 QA 中间文件在 Git 忽略的 `output/pet-interactions/`。最终运行素材在 `Sources/App/Resources/BuiltinPets/{pet}/`，已随 SwiftPM 和 macOS 应用包复制；运行不需要项目外的素材目录。

## 验证

`./scripts/test.sh --filter 'PetInteractionTests|PetRelay|QuietPetAnimationTests|LocalizationParityTests'` 检查附加素材、循环兼容、一次播放、取消、重复点击、减少动态效果、协议兼容、过期、去重、回击和简体中文覆盖。完整回归使用 `./scripts/test.sh`，服务端使用 `build/relay-venv/bin/python -m unittest discover -s server/agentpet-relay -v`。测试使用独立偏好与临时数据，不调用模型、不访问真实配对。

设置 `AGENTPET_RELAY_TEST_URL=http://127.0.0.1:端口/` 可运行 `isolatedLocalRelayRoundTripSynchronizesBothPetsAndReplies`，在本机隔离中转上创建两个临时身份，验证完整 Swift 客户端接口链路；只接受 localhost 地址。离屏渲染可通过 `AGENTPET_UI_SNAPSHOT_DIR` 输出截图，不显示窗口。
