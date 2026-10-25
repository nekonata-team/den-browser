// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DenDemo",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "den-demo", targets: ["DenDemo"])
    ],
    dependencies: [
        .package(path: "../DenDomain"),
        .package(path: "../DenInfrastructure"),
    ],
    targets: [
        .executableTarget(
            name: "DenDemo",
            dependencies: [
                "DenDomain",
                "DenInfrastructure",
            ],
            path: "Sources"
        )
    ],
    swiftLanguageModes: [.v6]
)
