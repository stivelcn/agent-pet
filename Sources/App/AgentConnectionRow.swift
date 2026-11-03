import SwiftUI
import AgentPetCore

/// Shared by onboarding and settings so detection/configuration/activity never disagree.
struct AgentConnectionRow: View {
    let agent: AgentIntegration
    @ObservedObject private var model = SettingsModel.shared

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: agent.displayName)
                Text(verbatim: model.connectionStatus(agent.kind))
                    .font(.caption)
                    .foregroundStyle(model.connectionErrors[agent.kind] != nil ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = agent.note {
                    Text(NSLocalizedString(note, comment: "client integration note"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if model.lastEvents[agent.kind] != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .help("已收到真实客户端事件")
            }
            Button(model.isInstalled(agent.kind) ? "断开" : "连接") {
                model.toggleInstall(agent.kind)
            }
            .disabled(!agent.isSupported || !LocalConfiguration.hookConfigurationEnabled ||
                      (!model.isInstalled(agent.kind) && model.detectedClients[agent.kind] == nil))
        }
    }
}
