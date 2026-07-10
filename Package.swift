// swift-tools-version: 6.0
import PackageDescription

// Standalone engine for the Fabric Math Expression node: no package dependencies and no
// Fabric / Metal / Satin, so `swift test` runs the whole correctness suite with
// no GPU or app. Transforms/quaternions use Apple `simd` at the port boundary, so
// it targets Apple platforms (macOS/iOS/visionOS).
let package = Package(
    name: "MathExpressionEngine",
    products: [
        .library(name: "MathExpressionEngine", targets: ["MathExpressionEngine"]),
    ],
    targets: [
        .target(name: "MathExpressionEngine"),
        .testTarget(name: "MathExpressionEngineTests", dependencies: ["MathExpressionEngine"]),
    ]
)
