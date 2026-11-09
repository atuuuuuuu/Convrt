// swift-tools-version:5.9
import PackageDescription

// The command-line `convrt` shares the app's engine files (symlinked from Convrt/Engine), so a conversion
// done in Terminal is exactly the conversion done by the wheel.
let package = Package(
    name: "convrt-cli",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ConvrtCore", path: "Sources/ConvrtCore"),
        .executableTarget(name: "convrt", dependencies: ["ConvrtCore"], path: "Sources/convrt"),
        .testTarget(name: "ConvrtCLITests", dependencies: ["ConvrtCore"], path: "Tests/ConvrtCLITests")
    ]
)
