// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "WeMacroDOF", platforms: [.macOS(.v14)], products: [.library(name: "DepthCore", targets: ["DepthCore"])], targets: [.target(name: "DepthCore"), .testTarget(name: "DepthCoreTests", dependencies: ["DepthCore"])])
