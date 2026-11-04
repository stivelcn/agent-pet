// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentPet",
    platforms: [.macOS(.v14)],
    dependencies: [],
    targets: [
        .target(
            name: "CZstd",
            path: "Vendor/CZstd",
            exclude: ["LICENSE", "VENDOR.md"],
            publicHeadersPath: ".",
            cSettings: [
                .define("ZSTD_DISABLE_ASM", to: "1"),
                .define("ZSTD_LEGACY_SUPPORT", to: "0"),
                .define("ZSTD_TRACE", to: "0"),
            ]
        ),
        .target(
            name: "AgentSpeedCore",
            dependencies: ["CZstd"],
            path: "Vendor/AgentSpeedCore"
        ),
        .target(
            name: "AgentPetCore",
            path: "Sources/AgentPetCore"
        ),
        .executableTarget(
            name: "agentpet",
            dependencies: ["AgentPetCore", "AgentSpeedCore"],
            path: "Sources/App"
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
