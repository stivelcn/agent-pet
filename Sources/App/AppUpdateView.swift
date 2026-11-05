import SwiftUI
import AppKit

struct AppUpdateView: View {
    @ObservedObject private var update: AppUpdateController
    @State private var confirmInstall = false
    init(update: AppUpdateController = .shared) { self.update = update }

    var body: some View {
        Section("Software update") {
            LabeledContent("Current version", value: update.currentVersion)
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
            if update.phase == .current { Label("You're up to date.", systemImage: "checkmark.circle").foregroundStyle(.green) }
            if update.phase == .downloading {
                ProgressView(value: update.progress) { Text("Downloading update…") } currentValueLabel: {
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
            Text("Updates replace only the application. Pet progress, usage history, settings and paired messages are kept. No update is installed without your confirmation.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Install this update and restart LuMate?", isPresented: $confirmInstall) {
            Button("Install and restart") { update.installAndRestart() }
        } message: {
            Text("Finish or close any unsent message first. Your current app will be backed up; user data and Keychain items will not be removed.")
        }
    }
}
