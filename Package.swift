// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 m1ll3t
import PackageDescription
let package = Package(name: "WeMacroMac", platforms: [.macOS(.v14)], products: [.executable(name: "WeMacroMac", targets: ["WeMacroMac"])], dependencies: [.package(path: "Packages/WeMacroDOF")], targets: [.executableTarget(name: "WeMacroMac", dependencies: [.product(name: "DepthCore", package: "WeMacroDOF")], swiftSettings: [.swiftLanguageMode(.v5)]), .testTarget(name: "WeMacroCoreTests", dependencies: ["WeMacroMac"])])
