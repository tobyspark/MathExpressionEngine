// swift-tools-version: 6.0
import PackageDescription

// Standalone, dependency-free engine for the Fabric Function Node.
// No dependency on Fabric / Metal / Satin, so `swift test` runs the whole
// correctness suite on a plain toolchain (macOS or Linux), no GPU required.
let package = Package(
    name: "FunctionEngine",
    products: [
        .library(name: "FunctionEngine", targets: ["FunctionEngine"]),
    ],
    targets: [
        .target(name: "FunctionEngine"),
        .testTarget(name: "FunctionEngineTests", dependencies: ["FunctionEngine"]),
    ]
)
