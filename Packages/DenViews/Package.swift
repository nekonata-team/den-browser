// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DenViews",
    platforms: [.macOS(.v26)],
    products: [.library(name: "DenViews", targets: ["DenViews"])],
    dependencies: [.package(path: "../DenPresentationModels"), .package(path: "../DenDomain")],
    targets: [
        .target(
            name: "DenViews",
            dependencies: [
                "DenPresentationModels",
                "DenDomain",
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
