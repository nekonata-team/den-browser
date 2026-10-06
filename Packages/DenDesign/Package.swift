// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DenDesign",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DenDesign", targets: ["DenDesign"])
    ],
    dependencies: [
        .package(url: "https://github.com/SFSafeSymbols/SFSafeSymbols.git", exact: "7.0.0")
    ],
    targets: [
        .target(
            name: "DenDesign",
            dependencies: [
                .product(name: "SFSafeSymbols", package: "SFSafeSymbols")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("NonescapableTypes"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
