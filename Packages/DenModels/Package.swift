// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DenModels",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DenModels", targets: ["DenModels"])
    ],
    dependencies: [.package(path: "../DenDomain"), .package(path: "../DenApplication")],
    targets: [
        .target(
            name: "DenModels",
            dependencies: ["DenDomain", "DenApplication"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("NonescapableTypes"),
            ]
        ),
        .testTarget(
            name: "DenModelsTests",
            dependencies: ["DenModels", "DenApplication", "DenDomain"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
