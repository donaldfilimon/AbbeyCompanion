// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "AbbeyCompanion",
    platforms: [
        .macOS(.v26)  // Foundation Models + SwiftData surfaces used by the companion
    ],
    products: [
        .library(name: "AbbeyCore", targets: ["AbbeyCore"]),
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
        .executableTarget(
            name: "AbbeyCompanion",
            dependencies: ["AbbeyCore"],
            path: "Sources/AbbeyCompanion",
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
        )
    ],
    swiftLanguageModes: [.v6]
)
