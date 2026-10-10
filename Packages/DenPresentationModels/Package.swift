// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DenPresentationModels",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DenPresentationModels", targets: ["DenPresentationModels"])
    ],
    dependencies: [.package(path: "../DenDomain")],
    targets: [
        .target(
            name: "DenPresentationModels",
            dependencies: ["DenDomain"],
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
