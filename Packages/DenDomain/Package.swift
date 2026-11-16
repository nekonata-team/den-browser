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
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("NonescapableTypes"),
            ]
        ),
        .testTarget(name: "DenDomainTests", dependencies: ["DenDomain"]),
    ],
    swiftLanguageModes: [.v6]
)
