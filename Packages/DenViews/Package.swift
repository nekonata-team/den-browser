// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DenViews",
    platforms: [.macOS(.v26)],
    products: [.library(name: "DenViews", targets: ["DenViews"])],
    dependencies: [
        .package(path: "../DenModels"), .package(path: "../DenDomain"),
        .package(url: "https://github.com/SFSafeSymbols/SFSafeSymbols.git", exact: "7.0.0"),
    ],
    targets: [
        .target(
            name: "DenViews",
            dependencies: [
                "DenModels",
                "DenDomain",
                .product(name: "SFSafeSymbols", package: "SFSafeSymbols"),
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
