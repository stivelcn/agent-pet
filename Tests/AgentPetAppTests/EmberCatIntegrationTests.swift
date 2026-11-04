import AppKit
import Foundation
import Metal
import Testing
import AgentSpeedCore
@testable import agentpet

@Suite(.serialized)
@MainActor
struct EmberCatIntegrationTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "local.agentpet.tests.embercat.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func migrationCopiesOnlyRequestedFeaturesAndPreservesExactJSON() throws {
        try withDefaults { defaults in
            var appearance = NotchFlameAppearance.standard
            appearance.brightness = 1.4
            let data = try JSONEncoder().encode(appearance)
            let palette = try JSONEncoder().encode(NotchFlamePalette.standard)
            let source: [String: Any] = ["notchFlamesEnabled": false, "showsTokenRate": true,
                "notchFlameAppearance": data, "notchFlamePalette": palette,
                "petStyle": "not-needed", "dockOrbitEnabled": true, "SUHasLaunchedBefore": true]
            #expect(EmberCatPreferenceMigration.importOnce(source: source, into: defaults) == 4)
            #expect(defaults.data(forKey: "notchFlameAppearance") == data)
            #expect(defaults.data(forKey: "notchFlamePalette") == palette)
            #expect(defaults.object(forKey: "petStyle") == nil)
            #expect(defaults.object(forKey: "dockOrbitEnabled") == nil)
            #expect(defaults.object(forKey: "SUHasLaunchedBefore") == nil)
            let settings = NotchFlameSettings(defaults: defaults)
            #expect(settings.appearance == appearance)
            #expect(!settings.isEnabled)
        }
    }

    @Test func migrationNeverOverwritesExistingPreferencesOrRunsTwice() {
        withDefaults { defaults in
            defaults.set(false, forKey: "showsTokenRate")
            defaults.set("existing-ledger", forKey: "agentpet.projectUsage")
            #expect(EmberCatPreferenceMigration.importOnce(
                source: ["showsTokenRate": true, "notchFlamesEnabled": false], into: defaults) == 1)
            #expect(!defaults.bool(forKey: "showsTokenRate"))
            #expect(EmberCatPreferenceMigration.importOnce(
                source: ["notchFlamesEnabled": true], into: defaults) == 0)
            #expect(!defaults.bool(forKey: "notchFlamesEnabled"))
            #expect(defaults.string(forKey: "agentpet.projectUsage") == "existing-ledger")
        }
    }

    @Test func missingLegacyDomainCanBeImportedLater() {
        withDefaults { defaults in
            #expect(EmberCatPreferenceMigration.importOnce(source: nil, into: defaults) == 0)
            #expect(!defaults.bool(forKey: EmberCatPreferenceMigration.markerKey))
            #expect(EmberCatPreferenceMigration.importOnce(source: ["showsTokenRate": true], into: defaults) == 1)
        }
    }

    @Test func migrationDoesNotChangeSourceAndSkipsIncorrectTypes() {
        withDefaults { defaults in
            let source: [String: Any] = ["notchFlameAppearance": "not-json-data", "showsTokenRate": "yes",
                                       "notchFlamesEnabled": true]
            #expect(EmberCatPreferenceMigration.importOnce(source: source, into: defaults) == 1)
            #expect(defaults.object(forKey: "notchFlameAppearance") == nil)
            #expect(defaults.object(forKey: "showsTokenRate") == nil)
            #expect(source["notchFlameAppearance"] as? String == "not-json-data")
            #expect(source["notchFlamesEnabled"] as? Bool == true)
        }
    }

    @Test func allIsolatedModesSkipLegacyImport() {
        #expect(EmberCatPreferenceMigration.allowsLegacyImport(environment: [:]))
        for env in [["AGENTPET_EMBERCAT_ENABLED": "0"],
                    ["AGENTPET_PREFERENCES_SUITE": "isolated"],
                    ["AGENTPET_DATA_DIR": "/tmp/isolated"]] {
            #expect(!EmberCatPreferenceMigration.allowsLegacyImport(environment: env))
        }
    }

    @Test func rateFormattingAndPrecisionAreStable() {
        #expect(EmberCatRateFormat.text(speed: 128.25) == "128.2 token/s")
        #expect(EmberCatRateFormat.text(speed: 128.25, precision: 2) == "128.25 token/s")
        #expect(EmberCatRateFormat.text(speed: 128.25, precision: 0) == "128 token/s")
        #expect(EmberCatRateFormat.text(speed: -1) == "0.0 token/s")
        #expect(EmberCatRateFormat.text(speed: .nan) == "0.0 token/s")
        #expect(EmberCatRateFormat.text(speed: .infinity) == "0.0 token/s")
    }

    @Test func scanningAndMissingSourcesAreNotPresentedAsMeasuredZero() {
        withDefaults { defaults in
            let module = EmberCatIntegration(defaults: defaults)
            defer { module.dispose() }
            #expect(module.menuBarText == "— token/s")
            var snapshot = SpeedSnapshot.empty
            snapshot.state = .noSources
            module.receive(snapshot)
            #expect(module.menuBarText == "— token/s")
            snapshot.state = .running
            module.receive(snapshot)
            #expect(module.menuBarText == "0.0 token/s")
        }
    }

    @Test func liveOutputNotTotalDrivesTheLabelAndNeverFeedsPetUsage() {
        withDefaults { defaults in
            let sentinel = Data("synthetic-isolated-ledger".utf8)
            defaults.set(sentinel, forKey: "agentpet.projectUsage")
            defaults.set(sentinel, forKey: "agentpet.care.v2")
            let module = EmberCatIntegration(defaults: defaults)
            defer { module.dispose() }
            var calls = 0
            module.onMenuBarChange = { calls += 1 }
            var snapshot = SpeedSnapshot.empty
            snapshot.state = .running
            snapshot.live = Rate(output: 42.25, total: 900)
            snapshot.liveEstimatedShare = 0.25
            module.receive(snapshot)
            #expect(module.speed == 42.25)
            #expect(module.menuBarText == "42.2 token/s")
            #expect(module.estimateDescription.contains("25%"))
            #expect(calls == 1)
            #expect(defaults.data(forKey: "agentpet.projectUsage") == sentinel)
            #expect(defaults.data(forKey: "agentpet.care.v2") == sentinel)
            #expect(!module.isRunning)
        }
    }

    @Test func displaySettingsPersistWithoutChangingFlameSettings() {
        withDefaults { defaults in
            let module = EmberCatIntegration(defaults: defaults)
            defer { module.dispose() }
            module.showsTokenRate = false
            module.ratePrecision = 2
            #expect(module.menuBarText.isEmpty)
            #expect(module.flameSettings.isEnabled)
            let reloaded = EmberCatIntegration(defaults: defaults)
            defer { reloaded.dispose() }
            #expect(!reloaded.showsTokenRate)
            #expect(reloaded.ratePrecision == 2)
        }
    }

    @Test func flameToggleUpdatesTheSettingsPanelAndPersists() {
        withDefaults { defaults in
            let module = EmberCatIntegration(defaults: defaults)
            defer { module.dispose() }
            module.setFlameEnabled(false)
            #expect(!module.flameEnabled)
            #expect(!NotchFlameSettings(defaults: defaults).isEnabled)
            module.setFlameEnabled(true)
            #expect(module.flameEnabled)
        }
    }

    @Test func disabledIntegrationStartsNoMonitorAndStopIsIdempotent() {
        withDefaults { defaults in
            let module = EmberCatIntegration(defaults: defaults)
            defer { module.dispose() }
            module.start(environment: ["AGENTPET_EMBERCAT_ENABLED": "0"])
            #expect(!module.isRunning)
            module.stop()
            module.stop()
            #expect(!module.isRunning)
        }
    }

    @Test func allSixAppearanceControlsRoundTripAndInvalidChangesAreRejected() {
        withDefaults { defaults in
            let settings = NotchFlameSettings(defaults: defaults)
            #expect(NotchFlameParameter.allCases.count == 6)
            for parameter in NotchFlameParameter.allCases {
                var appearance = settings.appearance
                appearance[keyPath: parameter.keyPath] = parameter.range.upperBound
                #expect(settings.setAppearance(appearance))
                #expect(NotchFlameSettings(defaults: defaults).appearance == appearance)
                appearance[keyPath: parameter.keyPath] = parameter.range.upperBound + 1
                #expect(!settings.setAppearance(appearance))
            }
        }
    }

    @Test func paletteThresholdsAndColorsPersistAcrossReloads() {
        withDefaults { defaults in
            let settings = NotchFlameSettings(defaults: defaults)
            let custom = NotchFlamePalette(bands: [.init(minimumSpeed: 0, hex: "#001122"),
                                                  .init(minimumSpeed: 37.5, hex: "#abcdef")])
            #expect(settings.setPalette(custom))
            let reloaded = NotchFlameSettings(defaults: defaults)
            #expect(reloaded.palette.bands[1].hex == "#ABCDEF")
            #expect(reloaded.palette.color(for: 37.49) == custom.bands[0].rgb)
            #expect(reloaded.palette.color(for: 37.5) == custom.bands[1].rgb)
        }
    }

    @Test func invalidStoredConfigurationFallsBackWithoutOverwritingOriginalBytes() {
        withDefaults { defaults in
            let original = Data("synthetic-invalid-json".utf8)
            defaults.set(original, forKey: "notchFlamePalette")
            defaults.set(original, forKey: "notchFlameAppearance")
            let settings = NotchFlameSettings(defaults: defaults)
            #expect(settings.palette == .standard)
            #expect(settings.appearance == .standard)
            #expect(defaults.data(forKey: "notchFlamePalette") == original)
        }
    }

    @Test func displaySelectionPrefersRealLaptopNotchAndFallsBackWhenClosed() throws {
        let external = NotchScreenSnapshot(name: "synthetic-external", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440))
        var laptop = NotchScreenSnapshot(name: "synthetic-laptop", frame: CGRect(x: 2560, y: 0, width: 1512, height: 982),
            safeAreaTop: 32, leftArea: CGRect(x: 2560, y: 950, width: 666, height: 32),
            rightArea: CGRect(x: 3406, y: 950, width: 666, height: 32), isBuiltIn: true)
        #expect(NotchDisplayProfile.select(from: [external, laptop])?.screenName == "synthetic-laptop")
        laptop.isActive = false
        #expect(NotchDisplayProfile.select(from: [external, laptop])?.screenName == "synthetic-external")
        let fallback = try #require(NotchDisplayProfile.select(from: [external]))
        #expect(fallback.anchorFrame.midX == external.frame.midX)
        #expect(fallback.notchFrame == nil)
    }

    @Test func metalShaderCompilesAndRendersFireOffscreenWithoutOpeningWindows() throws {
        // Real GPU render, but no NSWindow, live transcript scan, or production preferences.
        let renderer = try NotchFlameRenderer()
        let geometry = NotchFlameGeometry(notchWidth: 180, notchHeight: 32)
        let lit = try renderer.image(geometry: geometry, time: 8.73, speed: 120, scale: 1)
        let idle = try renderer.image(geometry: geometry, time: 8.73, speed: 0, scale: 1)
        #expect(lit.width == Int(geometry.size.width))
        #expect(lit.height == Int(geometry.size.height))
        let litData = try #require(lit.dataProvider?.data) as Data
        let idleData = try #require(idle.dataProvider?.data) as Data
        #expect(litData.contains { $0 != 0 })
        #expect(idleData.allSatisfy { $0 == 0 })
        #expect(litData != idleData)
    }
}
