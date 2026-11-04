# LuMate 品牌展示素材

- `lulu.png` / `lumei.png`：从内置精灵图的第一个 192×208 单元原样截取，保留透明通道。
- `lumate-pets.png`：两张原始帧并排合成的透明 PNG，供 README 首屏展示。
- `lumate-social-preview.png`：1280×640 的 GitHub 社交分享封面，角色仅做等比缩放，无重新生成或造型修改。

这些图由 `scripts/generate-brand-assets.py` 生成。脚本需要 Pillow；社交封面使用 macOS 自带 Arial Rounded / Arial Unicode 字体。重新生成不会改写应用内原始精灵图，图片也是 README 的本地相对引用，不依赖外链。

## 来源与许可

噜噜来自用户提供的 Petdex 外观包，原提交者为 **小艺 粥.**；噜妹使用用户确认的待机素材。详细来源与限制见 [内置形象说明](../../Sources/App/Resources/BuiltinPets/README.md) 和 [第三方说明](../../THIRD_PARTY_NOTICES.md)。

**不将角色或其衍生展示图重新声明为 MIT、原创或独占商标素材。公开展示与再次分发的权利需由维护者单独核实。** 本目录不改变原素材的权利归属。

## GitHub 分享封面设置

在仓库 **Settings → General → Social preview → Edit → Upload an image** 上传 `lumate-social-preview.png`。README 中展示图片不等于已经设置 GitHub 的社交分享封面；是否生效以仓库设置和分享预览为准。
