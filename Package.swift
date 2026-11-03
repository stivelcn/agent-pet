// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentPet",
    platforms: [.macOS(.v13)],
    dependencies: [],
    targets: [
        .target(
            name: "AgentPetCore",
            path: "Sources/AgentPetCore"
        ),
        .executableTarget(
            name: "agentpet",
            dependencies: ["AgentPetCore"],
            path: "Sources/App",
            resources: [.copy("Resources/donate-vietqr.png")]
        ),
        .testTarget(
            name: "AgentPetCoreTests",
            dependencies: ["AgentPetCore"],
            path: "Tests/AgentPetCoreTests"
        ),
        .testTarget(
            name: "AgentPetAppTests",
            dependencies: ["agentpet"],
            path: "Tests/AgentPetAppTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
