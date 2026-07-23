// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "AbbeyCompanion",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "AbbeyCore", targets: ["AbbeyCore"]),
        .library(name: "AbbeyCompanionKit", targets: ["AbbeyCompanionKit"]),
        .executable(name: "AbbeyCompanion", targets: ["AbbeyCompanion"])
    ],
    targets: [
        .target(
            name: "AbbeyCore",
            path: "Sources/AbbeyCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "AbbeyCompanionKit",
            dependencies: ["AbbeyCore"],
            path: "Sources/AbbeyCompanionKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "AbbeyCompanion",
            dependencies: ["AbbeyCompanionKit"],
            path: "Sources/AbbeyCompanionApp",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AbbeyCoreTests",
            dependencies: ["AbbeyCore"],
            path: "Tests/AbbeyCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AbbeyCompanionKitTests",
            dependencies: ["AbbeyCompanionKit", "AbbeyCore"],
            path: "Tests/AbbeyCompanionKitTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
