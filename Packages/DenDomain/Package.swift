// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DenDomain",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DenDomain", targets: ["DenDomain"])
    ],
    targets: [
        .target(
            name: "DenDomain",
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
