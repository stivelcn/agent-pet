import Foundation
import Testing
import CryptoKit
import AgentPetCore
@testable import agentpet

private final class UpdateMockProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var wire = (status: 200, data: Data(), delay: 0.0)
    nonisolated(unsafe) private static var routes: [URL: (status: Int, data: Data)] = [:]
    nonisolated(unsafe) private static var seen: [URL] = []
    static var requests: [URL] { lock.withLock { seen } }
    static func route(_ url: URL, status: Int = 200, data: Data) {
        lock.withLock { routes[url] = (status, data) }
    }
    static func respond(status: Int = 200, data: Data, delay: Double = 0) {
        lock.withLock { wire = (status, data, delay); routes = [:]; seen = [] }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.lock.withLock {
            if let url = request.url {
                Self.seen.append(url)
                if let route = Self.routes[url] { return (status: route.status, data: route.data, delay: 0.0) }
            }
            return Self.wire
        }
        if reply.delay > 0 { Thread.sleep(forTimeInterval: reply.delay) }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": String(reply.data.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Live smoke tests intercept only the primary endpoints; backup HTTPS uses native URLSession.
private final class UnavailableGitHubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        ["github.com", "api.github.com"].contains(request.url?.host ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct AppUpdateTests {
    private let contents = Data("isolated DMG test fixture".utf8)
    private func json(version: String = "v0.2.2", name: String = "LuMate-0.2.2-universal.dmg",
                      url: String? = nil, digest: String? = nil, draft: Bool = false, prerelease: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "tag_name": version, "body": "Test update notes", "draft": draft, "prerelease": prerelease,
            "assets": [["name": name, "size": contents.count,
                "digest": digest ?? "sha256:" + SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined(),
                "browser_download_url": url ?? "https://github.com/stivelcn/lumate/releases/download/\(version)/\(name)"]]
        ])
    }
    private func release(_ data: Data) throws -> GitHubRelease { try JSONDecoder().decode(GitHubRelease.self, from: data) }
    private func folder() throws -> URL {
        let result = FileManager.default.temporaryDirectory.appendingPathComponent("lumate-update-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }
    private func controller(_ directory: URL? = nil, defaults: UserDefaults = LocalPreferences.defaults,
                            canInstall: @escaping @MainActor () -> Bool = { false },
                            installer: (@MainActor () -> Void)? = nil) -> AppUpdateController {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateMockProtocol.self]
        return AppUpdateController(session: URLSession(configuration: config), downloadDirectory: directory, defaults: defaults, automaticInstallAllowed: canInstall, automaticInstaller: installer, currentVersion: "0.2.1")
    }
    private func awaitIdle(_ model: AppUpdateController) async throws {
        for _ in 0..<300 {
            if !model.busy { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Update operation did not finish")
    }

    @Test func versionsCompareNumericallyAndRejectPrereleaseOrMalformedTags() throws {
        #expect(try #require(ReleaseVersion("0.10.0")) > #require(ReleaseVersion("v0.9.9")))
        #expect(ReleaseVersion("v1.2") == ReleaseVersion("1.2.0"))
        for value in ["", "v", "1", "0..1", "1.2.3.4", "1.2.-1", "1.2.3-beta", "1.2.3+test", " 1.2.3", "1.٢.3"] {
            #expect(ReleaseVersion(value) == nil)
        }
    }
    @Test func onlyNewerPublishedStableVersionsAreUpdates() throws {
        #expect(try release(json()).isNewer(than: "0.2.1"))
        #expect(try !release(json()).isNewer(than: "0.2.2"))
        #expect(try !release(json()).isNewer(than: "0.3.0"))
        #expect(try !release(json(draft: true)).isNewer(than: "0.2.1"))
        #expect(try !release(json(prerelease: true)).isNewer(than: "0.2.1"))
    }
    @Test func selectsOnlyVerifiedAssetsInThisRepositoryForTheRightMac() throws {
        let universal = try release(json())
        for arch in ["arm64", "x86_64"] { #expect(universal.dmg(architecture: arch)?.name == "LuMate-0.2.2-universal.dmg") }
        let arm = try release(json(name: "LuMate-0.2.2-arm64.dmg"))
        #expect(arm.dmg(architecture: "arm64") != nil)
        #expect(arm.dmg(architecture: "x86_64") == nil)
        for url in ["http://github.com/stivelcn/lumate/releases/download/v0.2.2/LuMate-0.2.2-universal.dmg",
                    "https://example.com/LuMate-0.2.2-universal.dmg",
                    "https://github.com/other/repo/releases/download/v0.2.2/LuMate-0.2.2-universal.dmg",
                    "https://github.com/stivelcn/lumate/releases/download/v0.2.2/LuMate-0.2.2-universal.dmg?anything=1"] {
            #expect(try release(json(url: url)).dmg(architecture: "arm64") == nil)
        }
        for hash in ["", "sha256:abc", "md5:" + String(repeating: "0", count: 64), "sha256:" + String(repeating: "g", count: 64)] {
            #expect(try release(json(digest: hash)).dmg(architecture: "arm64") == nil)
        }
        #expect(try release(json(name: "Other.app.dmg")).dmg(architecture: "arm64") == nil)
    }
    @Test func checkHandlesAvailableCurrentMissingRateLimitedAndBadResponses() async throws {
        let model = controller()
        UpdateMockProtocol.respond(data: try json())
        model.check(); try await awaitIdle(model)
        #expect(model.phase == .available)
        #expect(model.release?.body == "Test update notes")
        UpdateMockProtocol.respond(data: try json(version: "v0.2.1"))
        model.check(); try await awaitIdle(model)
        #expect(model.phase == .current)
        for status in [404, 403, 429, 500] {
            UpdateMockProtocol.respond(status: status, data: Data())
            model.check(); try await awaitIdle(model)
            #expect(model.error != nil)
            #expect(!model.busy)
        }
        UpdateMockProtocol.respond(data: Data("not json".utf8))
        model.check(); try await awaitIdle(model)
        #expect(model.error != nil)
    }
    @Test func downloadVerifiesBytesAndNeverOverwritesExistingFiles() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = controller(directory)
        UpdateMockProtocol.respond(data: try json())
        model.check(); try await awaitIdle(model)
        let existing = directory.appendingPathComponent("LuMate-0.2.2-universal.dmg")
        try Data("keep me".utf8).write(to: existing)
        UpdateMockProtocol.respond(data: contents)
        model.download(); try await awaitIdle(model)
        #expect(model.error == nil)
        #expect(model.phase == .ready)
        let downloaded = try #require(model.downloadedURL)
        #expect(downloaded != existing)
        #expect(try Data(contentsOf: downloaded) == contents)
        #expect(try Data(contentsOf: existing) == Data("keep me".utf8))
    }
    @Test func failedOrTamperedDownloadsStayRetryable() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = controller(directory)
        UpdateMockProtocol.respond(data: try json())
        model.check(); try await awaitIdle(model)
        UpdateMockProtocol.respond(status: 500, data: Data())
        model.download(); try await awaitIdle(model)
        #expect(model.phase == .available)
        #expect(model.downloadedURL == nil)
        UpdateMockProtocol.respond(data: Data(repeating: 0, count: contents.count))
        model.download(); try await awaitIdle(model)
        #expect(model.error != nil)
        #expect(model.downloadedURL == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        UpdateMockProtocol.respond(data: contents)
        model.download(); try await awaitIdle(model)
        #expect(model.phase == .ready)
    }
    @Test func cancellationDoesNotLeaveAnInstallablePartialDownload() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = controller(directory)
        UpdateMockProtocol.respond(data: try json())
        model.check(); try await awaitIdle(model)
        UpdateMockProtocol.respond(data: contents, delay: 0.3)
        model.download()
        model.cancelDownload()
        try await awaitIdle(model)
        #expect(model.phase == .available)
        #expect(model.downloadedURL == nil)
        #expect(model.error == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
    @Test func metadataFallsBackToIndependentServerWhenGitHubIsUnavailable() async throws {
        let model = controller()
        UpdateMockProtocol.respond(status: 503, data: Data())
        UpdateMockProtocol.route(GitHubRelease.mirrorAPIURL, data: try json())
        model.check(); try await awaitIdle(model)
        #expect(model.phase == .available)
        #expect(model.error == nil)
        #expect(UpdateMockProtocol.requests == [GitHubRelease.apiURL, GitHubRelease.mirrorAPIURL])
    }

    @Test func downloadUsesGitHubFirstThenImmediatelyUsesVerifiedMirror() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = controller(directory)
        let metadata = try release(json())
        let asset = try #require(metadata.dmg(architecture: "arm64"))
        let mirror = try #require(metadata.mirrorURL(for: asset))
        #expect(mirror.absoluteString == "https://imagepro.ycgod.online/lumate-updates/v0.2.2/LuMate-0.2.2-universal.dmg")
        UpdateMockProtocol.respond(data: try json())
        model.check(); try await awaitIdle(model)
        UpdateMockProtocol.respond(status: 503, data: Data())
        UpdateMockProtocol.route(mirror, data: contents)
        model.download(); try await awaitIdle(model)
        #expect(model.phase == .ready)
        #expect(model.usingMirror)
        #expect(model.error == nil)
        #expect(UpdateMockProtocol.requests == [asset.browserDownloadURL, mirror])
        #expect(try Data(contentsOf: #require(model.downloadedURL)) == contents)
    }

    @Test func corruptPrimaryFallsBackButBothSourcesMustPassSameChecksum() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = controller(directory)
        let metadata = try release(json())
        let asset = try #require(metadata.dmg(architecture: "arm64"))
        let mirror = try #require(metadata.mirrorURL(for: asset))
        UpdateMockProtocol.respond(data: try json())
        model.check(); try await awaitIdle(model)
        UpdateMockProtocol.respond(data: Data(repeating: 0, count: contents.count))
        UpdateMockProtocol.route(mirror, data: contents)
        model.download(); try await awaitIdle(model)
        #expect(model.phase == .ready)
        try FileManager.default.removeItem(at: #require(model.downloadedURL))
        UpdateMockProtocol.respond(data: Data(repeating: 0, count: contents.count))
        model.download(); try await awaitIdle(model)
        #expect(model.downloadedURL == nil)
        #expect(model.error != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func successfulPrimaryAndUserCancellationNeverStartMirrorDownload() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = controller(directory)
        UpdateMockProtocol.respond(data: try json())
        model.check(); try await awaitIdle(model)
        UpdateMockProtocol.respond(data: contents)
        model.download(); try await awaitIdle(model)
        #expect(model.phase == .ready)
        #expect(UpdateMockProtocol.requests.count == 1)
        UpdateMockProtocol.respond(data: contents, delay: 0.3)
        model.download(); model.cancelDownload(); try await awaitIdle(model)
        #expect(!UpdateMockProtocol.requests.contains { $0.host == "imagepro.ycgod.online" })
        #expect(model.downloadedURL == nil)
    }

    @Test func automaticPreferencesAreOptInPersistAndDisableTogether() throws {
        let suite = "lumate-update-preferences-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = controller(defaults: defaults)
        #expect(!model.automaticCheckEnabled && !model.automaticInstallEnabled)
        model.setAutomaticInstall(true)
        #expect(model.automaticCheckEnabled && model.automaticInstallEnabled)
        let restored = controller(defaults: defaults)
        #expect(restored.automaticCheckEnabled && restored.automaticInstallEnabled)
        restored.setAutomaticCheck(false)
        #expect(!restored.automaticCheckEnabled && !restored.automaticInstallEnabled)
        #expect(!controller(defaults: defaults).automaticInstallEnabled)
    }

    @Test func automaticPipelineDownloadsThenWaitsForUnsentMessagesAndResumes() async throws {
        let suite = "lumate-update-automatic-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        final class InstallationState { var allowed = false; var count = 0 }
        let installation = InstallationState()
        let model = controller(directory, defaults: defaults, canInstall: { installation.allowed }, installer: { installation.count += 1 })
        UpdateMockProtocol.respond(data: contents)
        UpdateMockProtocol.route(GitHubRelease.apiURL, data: try json())
        model.checkAutomaticallyIfNeeded()
        #expect(UpdateMockProtocol.requests.isEmpty)
        model.setAutomaticInstall(true)
        model.checkAutomaticallyIfNeeded()
        try await awaitIdle(model)
        #expect(model.phase == .ready)
        #expect(installation.count == 0)
        installation.allowed = true
        model.checkAutomaticallyIfNeeded()
        #expect(installation.count == 1)
        let restarted = controller(directory, defaults: defaults)
        #expect(restarted.phase == .ready)
        #expect(restarted.downloadedURL == model.downloadedURL)
        #expect(restarted.release?.tagName == "v0.2.2")
    }

    @Test func checkOnlyAutomationDoesNotDownloadAndRespectsSixHourInterval() async throws {
        let suite = "lumate-update-interval-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = controller(defaults: defaults)
        model.setAutomaticCheck(true)
        UpdateMockProtocol.respond(data: try json())
        let now = Date()
        model.checkAutomaticallyIfNeeded(now: now); try await awaitIdle(model)
        #expect(model.phase == .available)
        #expect(model.downloadedURL == nil)
        #expect(UpdateMockProtocol.requests.count == 1)
        model.checkAutomaticallyIfNeeded(now: now.addingTimeInterval(300)); try await awaitIdle(model)
        #expect(UpdateMockProtocol.requests.count == 1)
        model.checkAutomaticallyIfNeeded(now: now.addingTimeInterval(6 * 3600)); try await awaitIdle(model)
        #expect(UpdateMockProtocol.requests.count == 2)
    }

    @Test func automaticCheckRecoversWhenReleaseWasPublishedWithoutVerifiedAssets() async throws {
        let suite = "lumate-update-incomplete-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = controller(defaults: defaults)
        model.setAutomaticInstall(true)
        UpdateMockProtocol.respond(data: try json(digest: "sha256:not-ready"))
        let now = Date()
        model.checkAutomaticallyIfNeeded(now: now); try await awaitIdle(model)
        #expect(model.phase == .available)
        #expect(model.asset == nil)
        UpdateMockProtocol.respond(data: try json(version: "v0.2.1"))
        model.checkAutomaticallyIfNeeded(now: now.addingTimeInterval(6 * 3600)); try await awaitIdle(model)
        #expect(model.phase == .current)
        #expect(UpdateMockProtocol.requests == [GitHubRelease.apiURL])
    }

    @Test func liveBackupDownloadWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["AGENTPET_MIRROR_LIVE_TESTS"] == "1" else { return }
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "lumate-update-live-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UnavailableGitHubProtocol.self]
        let model = AppUpdateController(session: URLSession(configuration: config), downloadDirectory: directory,
                                        defaults: defaults, currentVersion: "0.0.0")
        model.check()
        for _ in 0..<600 {
            if !model.busy { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(model.error == nil)
        #expect(model.phase == .available)
        model.download()
        for _ in 0..<600 {
            if !model.busy { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(model.error == nil)
        #expect(model.phase == .ready)
        #expect(model.usingMirror)
        try UpdateInstaller.verifyDownload(#require(model.downloadedURL), asset: #require(model.asset))
    }

    @Test func installerRejectsIncompleteOrChangedDiskImages() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("test.dmg")
        let asset = try #require(release(json()).dmg(architecture: "arm64"))
        try contents.write(to: file)
        try UpdateInstaller.verifyDownload(file, asset: asset)
        try Data("truncated".utf8).write(to: file)
        #expect(throws: (any Error).self) { try UpdateInstaller.verifyDownload(file, asset: asset) }
        try Data(repeating: 0, count: contents.count).write(to: file)
        #expect(throws: (any Error).self) { try UpdateInstaller.verifyDownload(file, asset: asset) }
    }
    @Test func installerRejectsDevelopmentAppsDiskImagesAndTranslocatedPaths() throws {
        #expect(throws: (any Error).self) { try UpdateInstaller.validateInstalled(Bundle.main.bundleURL) }
        #expect(throws: (any Error).self) { try UpdateInstaller.validateInstalled(URL(fileURLWithPath: "/Volumes/LuMate/LuMate.app")) }
        #expect(throws: (any Error).self) { try UpdateInstaller.validateInstalled(URL(fileURLWithPath: "/private/var/AppTranslocation/test/LuMate.app")) }
    }
    @Test func shellArgumentsRemainLiteralEvenWithSpacesQuotesAndMetacharacters() throws {
        let value = "hello ' world; $(touch /tmp/NEVER-CREATE-LUMATE) \" end"
        let result = try UpdateInstaller.run("/bin/sh", ["-c", "printf '%s' " + UpdateInstaller.shellQuote(value)])
        #expect(result.status == 0)
        #expect(result.output == value)
    }
    @Test func bundleSwapAndRollbackPreserveOldAppAndAllAdjacentUserData() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = directory.appendingPathComponent("Lu Mate's.app")
        let source = directory.appendingPathComponent("new.app")
        let backup = directory.appendingPathComponent(".LuMate-backup-test.app")
        let candidate = directory.appendingPathComponent(".LuMate-install-test.app")
        for app in [old, source] { try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true) }
        try Data("old".utf8).write(to: old.appendingPathComponent("version"))
        try Data("new".utf8).write(to: source.appendingPathComponent("version"))
        let userData = directory.appendingPathComponent("pet-messages.json")
        try Data("do not modify my history".utf8).write(to: userData)
        let script = try #require(UpdateInstaller.bundledScript)
        let args = [script.path, "swap", source.path, old.path, backup.path, candidate.path]
        #expect(try UpdateInstaller.run("/bin/sh", args).status == 0)
        #expect(try String(contentsOf: old.appendingPathComponent("version"), encoding: .utf8) == "new")
        #expect(try String(contentsOf: backup.appendingPathComponent("version"), encoding: .utf8) == "old")
        #expect(try UpdateInstaller.run("/bin/sh", [script.path, "rollback", source.path, old.path, backup.path, candidate.path]).status == 0)
        #expect(try String(contentsOf: old.appendingPathComponent("version"), encoding: .utf8) == "old")
        #expect(try String(contentsOf: userData, encoding: .utf8) == "do not modify my history")
    }
    @Test func failedPreparationNeverMovesTheInstalledApplication() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = directory.appendingPathComponent("LuMate.app")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let marker = old.appendingPathComponent("version")
        try contents.write(to: marker)
        let script = try #require(UpdateInstaller.bundledScript)
        let args = [script.path, "swap", directory.appendingPathComponent("missing.app").path, old.path,
                    directory.appendingPathComponent(".LuMate-backup-test.app").path,
                    directory.appendingPathComponent(".LuMate-install-test.app").path]
        #expect(try UpdateInstaller.run("/bin/sh", args).status != 0)
        #expect(try Data(contentsOf: marker) == contents)
    }
    private func signedApp(_ url: URL, version: String) throws {
        let macOS = url.appendingPathComponent("Contents/MacOS")
        let resources = url.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        // macOS 27's system /usr/bin/true is arm64e-only; compile a genuine native arm64/x86 fixture.
        let source = url.deletingLastPathComponent().appendingPathComponent("fixture-main.c")
        try "int main(void) { return 0; }".write(to: source, atomically: true, encoding: .utf8)
        let compiled = try UpdateInstaller.run("/usr/bin/xcrun", ["clang", source.path, "-o", macOS.appendingPathComponent("agentpet").path])
        #expect(compiled.status == 0, "Compiling fixture failed: \(compiled.output)")
        let metadata: [String: Any] = ["CFBundleIdentifier": LocalConfiguration.releaseIdentifier,
            "CFBundleExecutable": "agentpet", "CFBundleShortVersionString": version,
            "CFBundleVersion": version, "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "14.0",
            "AgentPetDevelopmentBuild": false]
        let plist = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try plist.write(to: url.appendingPathComponent("Contents/Info.plist"))
        try Data("signed resource".utf8).write(to: resources.appendingPathComponent("fixture.txt"))
        let result = try UpdateInstaller.run("/usr/bin/codesign", ["--force", "--sign", "-", url.path])
        #expect(result.status == 0, "Signing fixture failed: \(result.output)")
    }
    @Test func validatesRealSignedApplicationsAndRejectsTamperingOrWrongVersions() throws {
        let directory = try folder().resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let installed = directory.appendingPathComponent("Installed.app")
        let next = directory.appendingPathComponent("LuMate.app")
        try signedApp(installed, version: "0.2.1")
        try signedApp(next, version: "0.2.2")
        try UpdateInstaller.validateInstalled(installed)
        try UpdateInstaller.validateApplication(next, version: "v0.2.2", installed: installed)
        #expect(throws: (any Error).self) { try UpdateInstaller.validateApplication(next, version: "v0.2.3", installed: installed) }
        #expect(throws: (any Error).self) { try UpdateInstaller.validateApplication(installed, version: "v0.2.1", installed: next) }
        try Data("modified after signing".utf8).write(to: next.appendingPathComponent("Contents/Resources/fixture.txt"))
        #expect(throws: (any Error).self) { try UpdateInstaller.validateApplication(next, version: "v0.2.2", installed: installed) }
    }
    @Test func realDMGPreparationDetachesVolumeAndTransactionPreservesData() throws {
        let directory = try folder().resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let installed = directory.appendingPathComponent("Installed.app")
        let distribution = directory.appendingPathComponent("distribution")
        try signedApp(installed, version: "0.2.1")
        try signedApp(distribution.appendingPathComponent("LuMate.app"), version: "0.2.2")
        let dmg = directory.appendingPathComponent("LuMate-0.2.2-universal.dmg")
        let create = try UpdateInstaller.run("/usr/bin/hdiutil", ["create", "-srcfolder", distribution.path, "-volname", "LuMateUpdateTest", "-format", "UDZO", dmg.path])
        #expect(create.status == 0, "DMG creation failed: \(create.output)")
        let bytes = try Data(contentsOf: dmg)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let asset = GitHubRelease.Asset(name: dmg.lastPathComponent, size: Int64(bytes.count), browserDownloadURL: URL(string: "https://github.com/stivelcn/lumate")!, digest: "sha256:" + hash)
        let script = try #require(UpdateInstaller.bundledScript)
        let plan = try UpdateInstaller.prepare(dmg: dmg, asset: asset, version: "v0.2.2", installed: installed, script: script, workspaceRoot: directory.appendingPathComponent("work"))
        let mounts = try UpdateInstaller.run("/usr/bin/hdiutil", ["info"])
        #expect(!mounts.output.contains(plan.directory.appendingPathComponent("mount").path))
        let userData = directory.appendingPathComponent("pet-progress.json")
        try contents.write(to: userData)
        try UpdateInstaller.execute(plan, mode: "swap")
        #expect(try UpdateInstaller.info(installed)["CFBundleShortVersionString"] as? String == "0.2.2")
        #expect(try UpdateInstaller.info(plan.backup)["CFBundleShortVersionString"] as? String == "0.2.1")
        #expect(try Data(contentsOf: userData) == contents)
        try UpdateInstaller.execute(plan, mode: "rollback")
        #expect(try UpdateInstaller.info(installed)["CFBundleShortVersionString"] as? String == "0.2.1")
        #expect(try Data(contentsOf: userData) == contents)
    }

}
