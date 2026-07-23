// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CursorUsage",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "CursorUsage", targets: ["CursorUsage"])
    ],
    targets: [
        .executableTarget(
            name: "CursorUsage",
            path: "Sources/CursorUsage"
        )
    ]
)
