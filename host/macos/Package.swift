// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeycapHost",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KeycapCore", targets: ["KeycapCore"]),
        .executable(name: "keycap-host", targets: ["KeycapHost"]),
    ],
    targets: [
        .target(name: "KeycapCore"),
        .executableTarget(
            name: "KeycapHost",
            dependencies: ["KeycapCore"]
        ),
        .testTarget(
            name: "KeycapCoreTests",
            dependencies: ["KeycapCore"]
        ),
        .testTarget(
            name: "KeycapHostTests",
            dependencies: ["KeycapHost"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
