// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sajilo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Sajilo", targets: ["Sajilo"]),
        .library(name: "SajiloCore", targets: ["SajiloCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Sajilo",
            dependencies: ["SajiloCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SajiloCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SajiloCoreTests",
            dependencies: ["SajiloCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
