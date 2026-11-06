import AppKit
import Combine
import Foundation
import AgentPetCore

private final class UpdateDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let report: @Sendable (Double) -> Void
    init(report: @escaping @Sendable (Double) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { report(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

@MainActor
final class AppUpdateController: ObservableObject {
    static let shared = AppUpdateController()
    enum Phase: Equatable { case idle, checking, current, available, downloading, verifying, ready, installing }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var release: GitHubRelease?
    @Published private(set) var downloadedURL: URL?
    @Published private(set) var progress: Double = 0
    @Published private(set) var error: String?
    private var operation: Task<Void, Never>?
    private let session: URLSession
    private let downloadDirectory: URL?
    let currentVersion: String

    init(session: URLSession = URLSession(configuration: .ephemeral),
         downloadDirectory: URL? = nil,
         currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.3") {
        self.session = session
        self.downloadDirectory = downloadDirectory
        self.currentVersion = currentVersion
    }
    var busy: Bool { [.checking, .downloading, .verifying, .installing].contains(phase) }
    var asset: GitHubRelease.Asset? {
        #if arch(arm64)
        release?.dmg(architecture: "arm64")
        #else
        release?.dmg(architecture: "x86_64")
        #endif
    }

    func check() {
        guard !busy else { return }
        phase = .checking; error = nil
        operation = Task {
            await checkLatest()
            operation = nil
        }
    }
    /// Kept separate for deterministic network tests without contacting real Releases.
    func checkLatest() async {
        do {
            var request = URLRequest(url: GitHubRelease.apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("LuMate/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw AppUpdateError.message("Could not check for updates. Please try again.") }
            if http.statusCode == 404 { throw AppUpdateError.message("No published release is available yet.") }
            if http.statusCode == 403 || http.statusCode == 429 { throw AppUpdateError.message("GitHub is rate limiting requests. Please try again later.") }
            guard http.statusCode == 200 else { throw AppUpdateError.message("Could not check for updates. Please try again.") }
            let next = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard !next.draft, !next.prerelease, ReleaseVersion(next.tagName) != nil,
                  ReleaseVersion(currentVersion) != nil else { throw AppUpdateError.message("The release version is not a valid stable version.") }
            if release?.tagName != next.tagName { downloadedURL = nil }
            release = next
            phase = next.isNewer(than: currentVersion) ? (downloadedURL == nil ? .available : .ready) : .current
            error = nil
        } catch {
            self.error = error.localizedDescription
            phase = downloadedURL != nil ? .ready : (release?.isNewer(than: currentVersion) == true ? .available : .idle)
        }
    }

    func download() {
        guard !busy, let asset, release?.isNewer(than: currentVersion) == true else { return }
        phase = .downloading; progress = 0; error = nil; downloadedURL = nil
        operation = Task {
            var temporary: URL?
            defer {
                if let temporary { try? FileManager.default.removeItem(at: temporary) }
                operation = nil
            }
            do {
                let reporter = UpdateDownloadProgress { [weak self] value in
                    Task { @MainActor in
                        if self?.phase == .downloading { self?.progress = value }
                    }
                }
                var request = URLRequest(url: asset.browserDownloadURL, timeoutInterval: 300)
                request.setValue("LuMate/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (url, response) = try await session.download(for: request, delegate: reporter)
                temporary = url
                try Task.checkCancellation()
                guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https" else {
                    throw AppUpdateError.message("The download failed. Please try again.")
                }
                phase = .verifying
                let verification = Task.detached { try UpdateInstaller.verifyDownload(url, asset: asset) }
                try await withTaskCancellationHandler { try await verification.value } onCancel: { verification.cancel() }
                try Task.checkCancellation()
                let downloads = try downloadDirectory ?? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                // Never overwrite another file in Downloads, including an older package with the same name.
                var destination = downloads.appendingPathComponent(asset.name)
                if FileManager.default.fileExists(atPath: destination.path) {
                    destination = downloads.appendingPathComponent(String(asset.name.dropLast(4)) + "-" + UUID().uuidString.prefix(8) + ".dmg")
                }
                try FileManager.default.moveItem(at: url, to: destination)
                temporary = nil
                downloadedURL = destination; progress = 1; phase = .ready
            } catch {
                phase = .available
                if !(error is CancellationError) && (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
            }
        }
    }

    func cancelDownload() { operation?.cancel() }

    func installAndRestart() {
        guard !busy, let dmg = downloadedURL, let asset, let release else { return }
        do {
            try UpdateInstaller.validateInstalled(Bundle.main.bundleURL)
            try saveUserState()
            guard let script = UpdateInstaller.bundledScript else { throw AppUpdateError.message("The update installer is missing. Please reinstall LuMate manually.") }
            phase = .installing; error = nil
            let installed = Bundle.main.bundleURL
            operation = Task {
                do {
                    let plan = try await Task.detached {
                        try UpdateInstaller.prepare(dmg: dmg, asset: asset, version: release.tagName, installed: installed, script: script)
                    }.value
                    // Check again after mounting/copying: the user may have typed or sent a message meanwhile.
                    try saveUserState()
                    let snapshot = LocalPreferences.defaults.persistentDomain(forName: LocalConfiguration.preferencesSuite) ?? [:]
                    let data = try PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0)
                    try data.write(to: plan.directory.appendingPathComponent("preferences-backup.plist"), options: .atomic)
                    try await Task.detached { try UpdateInstaller.execute(plan, mode: "swap") }.value
                    do {
                        guard LocalPreferences.defaults.synchronize() else { throw AppUpdateError.message("User data could not be saved. Installation was stopped.") }
                        try UpdateInstaller.launchRestarter(plan, processID: ProcessInfo.processInfo.processIdentifier)
                    }
                    catch {
                        try await Task.detached { try UpdateInstaller.execute(plan, mode: "rollback") }.value
                        throw error
                    }
                    NSApp.terminate(nil)
                } catch {
                    self.error = error.localizedDescription
                }
                phase = .ready
                operation = nil
            }
        } catch { self.error = error.localizedDescription }
    }

    private func saveUserState() throws {
        try PetWindowController.shared.prepareForUpdate()
        try PetRelayController.shared.saveForUpdate()
        try PetCareController.shared.saveForUpdate()
        guard LocalPreferences.defaults.synchronize() else { throw AppUpdateError.message("User data could not be saved. Installation was stopped.") }
    }
}
