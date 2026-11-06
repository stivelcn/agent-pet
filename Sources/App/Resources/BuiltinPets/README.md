# Built-in appearances / 内置形象

- **噜噜 (`lulu`)**: exact sprite and original manifest copied from the user's installed `lulu-7` pack. Original catalog attribution: `petdex`, submitted by `小艺 粥.`. The app displays the short name 噜噜; original metadata is retained in `lulu/pet.json`. No additional license or redistribution rights are asserted for this artwork.
- **噜妹 (`lumei`)**: user-approved idle materials v1, 2026-11-04. Original reference SHA-256: `5e51c8e5a168a5719c17ab83bc81d928f735903c7b7f9284239238684423df3f`. Six fixed 192×208 RGBA cells, 3.2-second loop at normal speed. Only idle/breathing/blinking; not a complete Codex v2 atlas. Two trailing transparent cells are unused. Source pixels have not been regenerated or resliced for this integration.

Local imported packs remain in the user's data directory. A valid local pack takes precedence over the bundled pack with the same ID. Built-in IDs cannot be deleted through the appearance picker. Check artwork rights separately before redistributing outside this local project.

## Additive interaction clips / 额外互动动作

2026-11-06：为噜噜、噜妹分别新增 `interactions.png` 与 `interactions.json`，四行依次是 `poke`、`poked`、`hug`、`peek`，每行六个 192×208 RGBA 格，按逐帧时长播放一次。原 `pet.json`、`spritesheet.*` 和日常待机选择保持原样。

生成服务为用户指定的 Aimindsky `images/edits`，模型 `gpt-image-2.6-flare`，参考图来自各自原待机首格。提示词由根目录 `model_prompt/images_edits.md` 的互动模板派生，实际请求文本保存在 `model_prompt/pet_interactions/`。只做确定性的透明背景清理、分离杂点清除、等比缩放和脚底对齐，没有程序绘制新的角色动作。每张动作图完成一次保留 alpha 的边缘去色处理。

这些是 LuMate 的四组附加动作，不宣称是完整 Codex v2 动作包。导入的旧宠物没有该可选文件时继续正常待机；预览页使用内置原形象，避免同 ID 本地导入包覆盖素材。当前仅支持本地预览，尚未通过配对链路传输形象或互动事件。
