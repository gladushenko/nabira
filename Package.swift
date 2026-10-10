// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nabira",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Nabira", targets: ["Nabira"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .executableTarget(
            name: "Nabira",
            dependencies: ["CSQLite"],
            path: "Sources/Nabira",
            resources: [.process("Resources")],
            plugins: [.plugin(name: "CompileLocalizations")]
        ),
        .testTarget(
            name: "NabiraTests",
            dependencies: ["Nabira", "CSQLite"],
            path: "Tests/NabiraTests"
        ),
        .plugin(name: "CompileLocalizations", capability: .buildTool())
    ]
)
