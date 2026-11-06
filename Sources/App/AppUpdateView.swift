import SwiftUI
import AppKit
import AgentPetCore

struct AppUpdateView: View {
    @ObservedObject private var update: AppUpdateController
    @State private var confirmInstall = false
    init(update: AppUpdateController = .shared) { self.update = update }

    var body: some View {
        Section("Software update") {
            LabeledContent("Current version", value: update.currentVersion)
            Toggle("Automatically check for updates", isOn: Binding(
                get: { update.automaticCheckEnabled }, set: { update.setAutomaticCheck($0) }))
                .accessibilityIdentifier("automatic-update-check").disabled(update.phase == .installing)
            Toggle("Automatically download and install updates", isOn: Binding(
                get: { update.automaticInstallEnabled }, set: { update.setAutomaticInstall($0) }))
                .accessibilityIdentifier("automatic-update-install").disabled(update.phase == .installing)
            Text("When enabled, updates download in the background and LuMate restarts when no message is being edited. macOS authorization may still be required.")
                .font(.caption).foregroundStyle(.secondary)
            if let release = update.release, release.isNewer(than: update.currentVersion) {
                LabeledContent("New version", value: release.tagName)
                if let notes = release.body, !notes.isEmpty {
                    ScrollView { Text(verbatim: notes).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 100)
                }
                if update.asset == nil {
                    Text("This release has no verified DMG for this Mac.").font(.caption).foregroundStyle(.orange)
                }
            }
            if update.phase == .ready && update.automaticInstallEnabled {
                Label("Downloaded. Waiting for LuMate to be idle before installing.", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if update.phase == .current { Label("You're up to date.", systemImage: "checkmark.circle").foregroundStyle(.green) }
            if update.phase == .downloading {
                ProgressView(value: update.progress) { Text(InterfaceText.format(update.usingMirror ? "Downloading from backup server…" : "Downloading update…")) } currentValueLabel: {
                    Text(update.progress, format: .percent.precision(.fractionLength(0)))
                }
            }
            if update.phase == .checking || update.phase == .verifying || update.phase == .installing {
                HStack {
                    ProgressView().controlSize(.small)
                    if update.phase == .checking { Text("Checking for updates…") }
                    else if update.phase == .verifying { Text("Verifying download…") }
                    else { Text("Preparing installation. macOS may ask for authorization…") }
                }.font(.caption)
            }
            if let error = update.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Button("Check for updates") { update.check() }
                    .disabled(update.busy).accessibilityIdentifier("check-for-updates")
                if update.phase == .downloading || update.phase == .verifying {
                    Button("Cancel download") { update.cancelDownload() }
                } else if !update.busy && update.asset != nil && update.release?.isNewer(than: update.currentVersion) == true {
                    if update.downloadedURL == nil {
                        Button("Download update") { update.download() }.buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("download-update")
                    } else {
                        Button("Install and restart") { confirmInstall = true }.buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("install-update")
                        Button("Download again") { update.download() }
                    }
                }
            }
            if let url = update.downloadedURL {
                Text(verbatim: url.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.disabled(update.busy)
                    Button("Open disk image") { NSWorkspace.shared.open(url) }.disabled(update.busy)
                }
            }
            Text("Updates use GitHub first and switch to the backup server on failure. Pet progress, usage history, settings and paired messages are kept.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Install this update and restart LuMate?", isPresented: $confirmInstall) {
            Button("Install and restart") { update.installAndRestart() }
        } message: {
            Text("Finish or close any unsent message first. Your current app will be backed up; user data and Keychain items will not be removed.")
        }
    }
}
