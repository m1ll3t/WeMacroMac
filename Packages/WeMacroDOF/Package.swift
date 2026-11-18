// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 m1ll3t
import PackageDescription
let package = Package(name: "WeMacroDOF", platforms: [.macOS(.v14)], products: [.library(name: "DepthCore", targets: ["DepthCore"])], targets: [.target(name: "DepthCore"), .testTarget(name: "DepthCoreTests", dependencies: ["DepthCore"])])
