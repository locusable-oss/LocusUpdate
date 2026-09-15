// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocusUpdate",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LocusUpdateCore", targets: ["LocusUpdateCore"]),
    ],
    targets: [
        .target(name: "LocusUpdateCore", path: "Sources/LocusUpdateCore"),
        .testTarget(name: "LocusUpdateCoreTests", dependencies: ["LocusUpdateCore"], path: "Tests/LocusUpdateCoreTests"),
    ]
)
