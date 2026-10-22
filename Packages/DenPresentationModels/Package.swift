// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DenPresentationModels",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DenPresentationModels", targets: ["DenPresentationModels"])
    ],
    dependencies: [.package(path: "../DenDomain"), .package(path: "../DenApplication")],
    targets: [
        .target(
            name: "DenPresentationModels",
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
            name: "DenPresentationModelsTests",
            dependencies: ["DenPresentationModels", "DenApplication", "DenDomain"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
