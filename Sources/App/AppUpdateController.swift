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
    @Published private(set) var usingMirror = false
    @Published private(set) var automaticCheckEnabled: Bool
    @Published private(set) var automaticInstallEnabled: Bool
    private let defaults: UserDefaults
    private var scheduler: Task<Void, Never>?
    private var automaticInstallSuppressed = false
    private var automaticRetryAfter = Date.distantPast
    private let automaticInstallAllowed: @MainActor () -> Bool
    private let automaticInstaller: (@MainActor () -> Void)?
    let currentVersion: String

    init(session: URLSession = URLSession(configuration: .ephemeral),
         downloadDirectory: URL? = nil,
         defaults: UserDefaults = LocalPreferences.defaults,
         automaticInstallAllowed: @escaping @MainActor () -> Bool = {
             NSApp.keyWindow == nil
                 && (try? PetWindowController.shared.prepareForUpdate()) != nil
                 && PetRelayController.shared.canUpdateApplication
         },
         automaticInstaller: (@MainActor () -> Void)? = nil,
         currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.7") {
        self.session = session
        self.downloadDirectory = downloadDirectory
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.automaticInstallAllowed = automaticInstallAllowed
        self.automaticInstaller = automaticInstaller
        let checksEnabled = defaults.bool(forKey: Self.checkPreferenceKey)
        automaticCheckEnabled = checksEnabled
        automaticInstallEnabled = defaults.bool(forKey: Self.installPreferenceKey) && checksEnabled
        if let data = defaults.data(forKey: Self.pendingDownloadKey),
           let pending = try? JSONDecoder().decode(PendingDownload.self, from: data),
           pending.release.isNewer(than: currentVersion),
           pending.path.hasPrefix("/"), pending.path.hasSuffix(".dmg"),
           FileManager.default.fileExists(atPath: pending.path) {
            release = pending.release
            downloadedURL = URL(fileURLWithPath: pending.path)
            phase = .ready
        }
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
            if automaticInstallEnabled && error == nil && phase == .available { await downloadLatest() }
            operation = nil
            attemptAutomaticInstall()
        }
    }

    /// GitHub is always first; the independent HTTPS mirror also covers API outages/rate limits.
    func checkLatest() async {
        do {
            var next: GitHubRelease?
            var lastError: Error = AppUpdateError.message("Could not check for updates. Please try again.")
            for url in [GitHubRelease.apiURL, GitHubRelease.mirrorAPIURL] {
                do {
                    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                    request.setValue("LuMate/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                    let (data, response) = try await session.data(for: request)
                    try Task.checkCancellation()
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                          response.url?.scheme == "https" else {
                        throw AppUpdateError.message("Could not check for updates. Please try again.")
                    }
                    let candidate = try JSONDecoder().decode(GitHubRelease.self, from: data)
                    guard !candidate.draft, !candidate.prerelease, ReleaseVersion(candidate.tagName) != nil,
                          ReleaseVersion(currentVersion) != nil else {
                        throw AppUpdateError.message("The release version is not a valid stable version.")
                    }
                    next = candidate
                    break
                } catch {
                    if Self.isCancellation(error) { throw error }
                    lastError = error
                }
            }
            guard let next else { throw lastError }
            if release?.tagName != next.tagName || release?.assets != next.assets {
                downloadedURL = nil
                defaults.removeObject(forKey: Self.pendingDownloadKey)
                automaticInstallSuppressed = false
            }
            release = next
            phase = next.isNewer(than: currentVersion) ? (downloadedURL == nil ? .available : .ready) : .current
            error = nil
        } catch {
            if !Self.isCancellation(error) { self.error = error.localizedDescription }
            phase = downloadedURL != nil ? .ready : (release?.isNewer(than: currentVersion) == true ? .available : .idle)
        }
    }

    func download() {
        guard !busy, asset != nil, release?.isNewer(than: currentVersion) == true else { return }
        phase = .downloading; progress = 0; error = nil
        automaticInstallSuppressed = false
        operation = Task {
            await downloadLatest()
            operation = nil
            attemptAutomaticInstall()
        }
    }

    private func downloadLatest() async {
        guard let asset, let release else { return }
        phase = .downloading; progress = 0; error = nil; downloadedURL = nil
        defaults.removeObject(forKey: Self.pendingDownloadKey)
        let urls = [asset.browserDownloadURL] + (release.mirrorURL(for: asset).map { [$0] } ?? [])
        var verified: URL?
        defer { if let verified { try? FileManager.default.removeItem(at: verified) } }
        do {
            var failure: Error = AppUpdateError.message("The download failed. Please try again.")
            for (index, source) in urls.enumerated() {
                var temporary: URL?
                do {
                    try Task.checkCancellation()
                    phase = .downloading; progress = 0
                    usingMirror = index > 0
                    let reporter = UpdateDownloadProgress { [weak self] value in
                        Task { @MainActor in
                            if self?.phase == .downloading { self?.progress = value }
                        }
                    }
                    // This is an inactivity timeout, so an actively transferring DMG can take longer.
                    var request = URLRequest(url: source, timeoutInterval: 15)
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
                    verified = url
                    break
                } catch {
                    if let temporary { try? FileManager.default.removeItem(at: temporary) }
                    if Self.isCancellation(error) { throw error }
                    failure = error
                }
            }
            guard let url = verified else { throw failure }
            let downloads = try downloadDirectory ?? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
            var destination = downloads.appendingPathComponent(asset.name)
            if FileManager.default.fileExists(atPath: destination.path) {
                destination = downloads.appendingPathComponent(String(asset.name.dropLast(4)) + "-" + UUID().uuidString.prefix(8) + ".dmg")
            }
            try FileManager.default.moveItem(at: url, to: destination)
            verified = nil
            downloadedURL = destination; progress = 1; phase = .ready
            defaults.set(try JSONEncoder().encode(PendingDownload(release: release, path: destination.path)), forKey: Self.pendingDownloadKey)
        } catch {
            phase = .available
            if !Self.isCancellation(error) {
                self.error = error.localizedDescription
                automaticRetryAfter = Date().addingTimeInterval(3600)
            } else { automaticInstallSuppressed = true }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    static let checkPreferenceKey = "agentpet.updates.automaticallyCheck"
    static let installPreferenceKey = "agentpet.updates.automaticallyInstall"
    private static let lastCheckKey = "agentpet.updates.lastAutomaticCheck"
    private static let pendingDownloadKey = "agentpet.updates.pendingDownload"
    private struct PendingDownload: Codable { let release: GitHubRelease; let path: String }

    func setAutomaticCheck(_ enabled: Bool) {
        automaticCheckEnabled = enabled
        defaults.set(enabled, forKey: Self.checkPreferenceKey)
        if !enabled { setAutomaticInstall(false) }
        else if scheduler != nil { checkAutomaticallyIfNeeded(force: true) }
    }

    func setAutomaticInstall(_ enabled: Bool) {
        automaticInstallEnabled = enabled
        defaults.set(enabled, forKey: Self.installPreferenceKey)
        automaticInstallSuppressed = false
        if enabled {
            automaticCheckEnabled = true
            defaults.set(true, forKey: Self.checkPreferenceKey)
            if scheduler != nil { checkAutomaticallyIfNeeded(force: true) }
        }
    }

    func startAutomaticUpdates() {
        guard scheduler == nil else { return }
        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkAutomaticallyIfNeeded()
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
        }
    }

    func stopAutomaticUpdates() { scheduler?.cancel(); scheduler = nil }

    /// Called on launch and once a minute; network checks are limited to once every six hours.
    func checkAutomaticallyIfNeeded(now: Date = Date(), force: Bool = false) {
        guard automaticCheckEnabled, !busy else { return }
        if phase == .ready {
            attemptAutomaticInstall()
            if busy { return }
        }
        let last = defaults.object(forKey: Self.lastCheckKey) as? Date
        let checkDue = last.map { now < $0 || now.timeIntervalSince($0) >= 6 * 3600 } ?? true
        if force || checkDue {
            defaults.set(now, forKey: Self.lastCheckKey)
            check()
        } else if automaticInstallEnabled, phase == .available, asset != nil,
                  !automaticInstallSuppressed, now >= automaticRetryAfter {
            download()
        }
    }

    private func attemptAutomaticInstall() {
        guard automaticInstallEnabled, !automaticInstallSuppressed, phase == .ready, automaticInstallAllowed() else { return }
        if let automaticInstaller { automaticInstallSuppressed = true; automaticInstaller(); return }
        // Development builds and read-only/translocated installs never prompt for silent replacement.
        guard (try? UpdateInstaller.validateInstalled(Bundle.main.bundleURL)) != nil else { return }
        let app = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: app.path),
              FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            error = NSLocalizedString("Automatic installation needs permission. Use Install and restart to authorize it.", comment: "")
            automaticInstallSuppressed = true
            return
        }
        installAndRestart(automatically: true)
    }

    func cancelDownload() { operation?.cancel() }

    func installAndRestart(automatically: Bool = false) {
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
                    if automatically && (!automaticInstallEnabled || !automaticInstallAllowed() || plan.needsAuthorization) {
                        phase = .ready
                        operation = nil
                        try? FileManager.default.removeItem(at: plan.directory)
                        return
                    }
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
                    if automatically { automaticInstallSuppressed = true }
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
