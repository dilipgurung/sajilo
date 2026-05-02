// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NepaliIME",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NepaliIME", targets: ["NepaliIME"]),
        .library(name: "NepaliIMECore", targets: ["NepaliIMECore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "NepaliIME",
            dependencies: ["NepaliIMECore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "NepaliIMECore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "NepaliIMECoreTests",
            dependencies: ["NepaliIMECore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
