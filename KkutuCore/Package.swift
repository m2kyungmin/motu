// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KkutuCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "KkutuCore", targets: ["KkutuCore"])],
    targets: [
        .target(name: "KkutuCore"),
        .testTarget(name: "KkutuCoreTests", dependencies: ["KkutuCore"]),
    ],
    swiftLanguageModes: [.v5]
)
