// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nabira",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Nabira", targets: ["Nabira"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .executableTarget(
            name: "Nabira",
            dependencies: ["CSQLite"],
            path: "Sources/Nabira",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "NabiraTests",
            dependencies: ["Nabira"],
            path: "Tests/NabiraTests",
            swiftSettings: [.unsafeFlags([
                "-Xfrontend", "-load-plugin-library", "-Xfrontend",
                "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
            ])]
        )
    ]
)
