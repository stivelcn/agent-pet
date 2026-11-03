import Foundation
import Testing
@testable import AgentPetCore

@Suite(.serialized)
final class LocalConfigurationTests {
    @Test func testReleaseAndDevelopmentDataAreIndependentOfUpstream() {
        let home = "/Users/synthetic-test-user"
        let release = AgentPetPaths.baseDirectory(home: home, development: false)
        let development = AgentPetPaths.baseDirectory(home: home, development: true)
        #expect((release) == (home + "/.agentpet-local"))
        #expect((development) == (home + "/.agentpet-local-dev"))
        #expect((release) != (development))
        #expect((release) != (home + "/.agentpet"))
    }

    @Test func testAbsoluteDataOverrideIsStandardized() {
        #expect((AgentPetPaths.baseDirectory(home: "/Users/test", development: true,
                                                  override: "/tmp/isolated/../agentpet-tests")) == ("/tmp/agentpet-tests"))
    }

    @Test func testRelativeAndEmptyOverridesAreIgnored() {
        for override in ["relative/data", "~/.agentpet", ""] {
            #expect((AgentPetPaths.baseDirectory(home: "/Users/test", development: true,
                                                      override: override)) == ("/Users/test/.agentpet-local-dev"))
        }
    }

    @Test func testRuntimePathsFollowTheSameDataRoot() {
        #expect((AgentPetPaths.socketPath) == (AgentPetPaths.baseDir + "/agentpet.sock"))
        #expect((AgentPetPaths.queueDir) == (AgentPetPaths.baseDir + "/queue"))
    }

    @Test func testPreferencesIdentitiesAreIndependent() {
        #expect((LocalConfiguration.releaseIdentifier) == ("local.agentpet"))
        #expect((LocalConfiguration.developmentIdentifier) == ("local.agentpet.dev"))
        #expect((LocalConfiguration.releaseIdentifier) != (LocalConfiguration.developmentIdentifier))
        let override = ProcessInfo.processInfo.environment["AGENTPET_PREFERENCES_SUITE"]
        let expected = override.flatMap { $0.isEmpty ? nil : $0 } ?? (LocalConfiguration.identifier + ".preferences")
        #expect((LocalConfiguration.preferencesSuite) == (expected))
    }

    @Test func testLocalConnectionsAreEnabledUnlessExplicitlyDisabled() {
        for development in [true, false] {
            #expect(LocalConfiguration.allowsHookConfiguration(development: development, optIn: nil))
            #expect(LocalConfiguration.allowsHookConfiguration(development: development, optIn: "1"))
            #expect(!(LocalConfiguration.allowsHookConfiguration(development: development, optIn: "0")))
        }
    }

    @Test func testPreferencesDoNotUseBundleIdentifierAndRemainWritable() {
        #expect((LocalConfiguration.preferencesSuite) != (Bundle.main.bundleIdentifier))
        let key = "synthetic.preference-regression"
        defer { LocalPreferences.defaults.removeObject(forKey: key) }
        LocalPreferences.defaults.set("中文", forKey: key)
        #expect((LocalPreferences.defaults.string(forKey: key)) == ("中文"))
    }
}
