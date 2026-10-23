// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DenInfrastructure",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DenInfrastructure", targets: ["DenInfrastructure"])
    ],
    dependencies: [.package(path: "../DenDomain")],
    targets: [
        .target(
            name: "DenInfrastructure",
            dependencies: ["DenDomain"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("NonescapableTypes"),
            ]
        ),
        .testTarget(name: "DenInfrastructureTests", dependencies: ["DenInfrastructure", "DenDomain"]),
    ],
    swiftLanguageModes: [.v6]
)
