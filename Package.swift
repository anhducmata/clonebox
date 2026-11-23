// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CloneBox",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CloneKit"),
        .executableTarget(name: "CloneBox", dependencies: ["CloneKit"]),
        .executableTarget(name: "clonebox-launcher"),
    ]
)
