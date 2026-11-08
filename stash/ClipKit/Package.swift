// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ClipKit", targets: ["ClipKit"])],
    targets: [
        .target(name: "ClipKit", resources: [.process("Resources")]),
        .testTarget(name: "ClipKitTests", dependencies: ["ClipKit"]),
    ],
    swiftLanguageModes: [.v6]
)
