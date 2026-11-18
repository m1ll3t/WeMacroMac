// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "WeMacroMac", platforms: [.macOS(.v14)], products: [.executable(name: "WeMacroMac", targets: ["WeMacroMac"])], dependencies: [.package(path: "Packages/WeMacroDOF")], targets: [.executableTarget(name: "WeMacroMac", dependencies: [.product(name: "DepthCore", package: "WeMacroDOF")], swiftSettings: [.swiftLanguageMode(.v5)]), .testTarget(name: "WeMacroCoreTests", dependencies: ["WeMacroMac"])])
