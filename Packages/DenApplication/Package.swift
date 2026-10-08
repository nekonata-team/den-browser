// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DenApplication",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DenApplication", targets: ["DenApplication"])
    ],
    dependencies: [.package(path: "../DenDomain")],
    targets: [
        .target(
            name: "DenApplication",
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
