// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DenIPCProtocol",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DenIPCProtocol", targets: ["DenIPCProtocol"])
    ],
    targets: [
        .target(name: "DenIPCProtocol"),
        .testTarget(name: "DenIPCProtocolTests", dependencies: ["DenIPCProtocol"]),
    ],
    swiftLanguageModes: [.v6]
)
