// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "AbbeyCompanion",
    platforms: [
        .macOS(.v27)
    ],
    products: [
        .library(name: "AbbeyCore", targets: ["AbbeyCore"]),
        .library(name: "AbbeyCompanionKit", targets: ["AbbeyCompanionKit"]),
        .library(name: "CoreAITools", targets: ["CoreAITools"]),
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
        .target(
            name: "CoreAITools",
            dependencies: ["AbbeyCore"],
            path: "Sources/CoreAITools",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "AbbeyCompanion",
            dependencies: ["AbbeyCompanionKit", "CoreAITools"],
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
            dependencies: ["AbbeyCompanionKit", "CoreAITools", "AbbeyCore"],
            path: "Tests/AbbeyCompanionKitTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "CoreAIToolsTests",
            dependencies: ["CoreAITools"],
            path: "Tests/CoreAIToolsTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
