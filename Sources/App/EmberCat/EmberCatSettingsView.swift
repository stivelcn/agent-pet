import SwiftUI

struct EmberCatSettingsView: View {
    @ObservedObject var integration: EmberCatIntegration
    var showFlamePreview: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("EmberCat 设置", systemImage: "flame.fill")
                    .font(.title2.bold())
                Text("只接入刘海火焰与实时速度；菜单栏继续使用智能桌宠的小爪子。")
                    .font(.callout).foregroundStyle(.secondary)
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("启用刘海火焰", isOn: Binding(
                            get: { integration.flameEnabled }, set: { integration.setFlameEnabled($0) }))
                            .accessibilityIdentifier("embercat-flame-toggle")
                        Text("跟随真实输出速度燃烧，空闲时渐隐。保留多屏适配、休眠恢复与系统减少动态效果支持。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("火焰设置与预览…", action: showFlamePreview)
                            .accessibilityIdentifier("embercat-flame-preview")
                        Text("配色区间、亮度、亮芯范围、通透度、焰尾长度、扰动和流速均在原生预览窗口调整。预览速度只影响预览，不写入使用记录。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                } label: { Label("刘海火焰", systemImage: "flame") }
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("在小爪子旁显示 token 速度", isOn: $integration.showsTokenRate)
                            .accessibilityIdentifier("embercat-speed-toggle")
                        Picker("速度小数位数", selection: $integration.ratePrecision) {
                            Text("整数").tag(0)
                            Text("1 位（原版默认）").tag(1)
                            Text("2 位").tag(2)
                        }
                        .pickerStyle(.menu).frame(maxWidth: 340)
                        Text(integration.snapshot.state == .running
                             ? EmberCatRateFormat.text(speed: integration.speed, precision: integration.ratePrecision)
                             : "— token/s")
                            .font(.system(.title2, design: .monospaced).bold())
                        Text(integration.statusLine).font(.callout)
                        Text("实时输出速度，约 3 秒窗口；不是累计 token，也不是套餐额度。")
                            .font(.caption).foregroundStyle(.secondary)
                        if integration.snapshot.state == .running {
                            Text(integration.estimateDescription).font(.caption).foregroundStyle(.secondary)
                        }
                        if !integration.snapshot.warnings.isEmpty {
                            Label("部分来源的记录可能不完整或不可读取；速度以当前可读取的记录为准。", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                } label: { Label("菜单栏速度", systemImage: "speedometer") }
                Text("沿用 EmberCat 的本地会话测速方式，不上传使用记录；不会把测速结果再次计入桌宠的用量或成长。原 EmberCat 配置保留不动，合并版的调整仅保存在智能桌宠中。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(minWidth: 520, minHeight: 600)
    }
}
